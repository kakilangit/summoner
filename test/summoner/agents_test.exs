defmodule Summoner.AgentsTest do
  use Summoner.DataCase

  alias Summoner.Agents
  alias Summoner.Agents.{Agent, AgentLink}

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    %{scope: scope, workspace: workspace, provider: provider}
  end

  # -------------------------------------------------------------------
  # CRUD
  # -------------------------------------------------------------------

  describe "create_agent/2" do
    setup :create_context

    test "creates a agent with valid attrs", %{scope: scope, workspace: w, provider: p} do
      attrs = valid_agent_attributes(w.id, p.id, %{name: "Agent Smith"})
      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.name == "Agent Smith"
      assert f.role == :autonomous
      assert f.max_concurrent_invocations == 1
      assert f.max_steps == 10
      assert f.max_tokens_per_invocation == 50_000
    end

    test "creates a worker agent", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs = valid_agent_attributes(w.id, p.id, %{role: :worker})
      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.role == :worker
      assert f.max_concurrent_invocations == 1
    end

    test "allows explicit max_concurrent_invocations", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs =
        valid_agent_attributes(w.id, p.id, %{max_concurrent_invocations: 5})

      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.max_concurrent_invocations == 5
    end

    test "keeps default max_concurrent_invocations=1 for workers", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs = valid_agent_attributes(w.id, p.id, %{role: :worker})
      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.max_concurrent_invocations == 1
    end

    test "requires mandatory fields", %{scope: scope} do
      assert {:error, changeset} = Agents.create_agent(scope, %{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:model]
      assert errors[:workspace_id]
      assert errors[:provider_id]
    end

    test "enforces unique name per workspace", %{scope: scope, workspace: w, provider: p} do
      agent_fixture(scope, w.id, p.id, %{name: "dupe"})
      attrs = valid_agent_attributes(w.id, p.id, %{name: "dupe"})
      assert {:error, changeset} = Agents.create_agent(scope, attrs)
      assert "has already been taken" in errors_on(changeset).workspace_id
    end
  end

  describe "list_agents/2" do
    setup :create_context

    test "returns agents for a workspace", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)
      assert [%Agent{id: id}] = Agents.list_agents(scope, w.id)
      assert id == agent.id
    end

    test "does not return agents from other workspaces", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      _agent = agent_fixture(scope, w.id, p.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert [] = Agents.list_agents(other_scope, other_workspace.id)
    end
  end

  describe "get_agent!/3" do
    setup :create_context

    test "returns the agent", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)
      fetched = Agents.get_agent!(scope, w.id, agent.id)
      assert fetched.id == agent.id
    end

    test "raises when agent belongs to another workspace", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      agent = agent_fixture(scope, w.id, p.id)

      other_scope = user_scope_fixture()
      other_workspace = workspace_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Agents.get_agent!(other_scope, other_workspace.id, agent.id)
      end
    end
  end

  describe "update_agent/3" do
    setup :create_context

    test "updates the agent", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)
      assert {:ok, updated} = Agents.update_agent(scope, agent, %{name: "new-name"})
      assert updated.name == "new-name"
    end
  end

  describe "delete_agent/2" do
    setup :create_context

    test "deletes the agent", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)
      assert {:ok, %Agent{}} = Agents.delete_agent(scope, agent)

      assert_raise Ecto.NoResultsError, fn ->
        Agents.get_agent!(scope, w.id, agent.id)
      end
    end
  end

  # -------------------------------------------------------------------
  # Linking
  # -------------------------------------------------------------------

  describe "link_agents/2" do
    setup :create_context

    test "links an agent to a worker", %{scope: scope, workspace: w, provider: p} do
      manager = agent_fixture(scope, w.id, p.id)
      worker = agent_fixture(scope, w.id, p.id, %{role: :worker})

      assert {:ok, %AgentLink{} = link} =
               Agents.link_agents(scope, %{
                 manager_id: manager.id,
                 worker_id: worker.id,
                 pattern: :delegate
               })

      assert link.pattern == :delegate
    end

    test "prevents self-linking", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)

      assert {:error, changeset} =
               Agents.link_agents(scope, %{
                 manager_id: agent.id,
                 worker_id: agent.id,
                 pattern: :delegate
               })

      assert "cannot link an agent to itself" in errors_on(changeset).worker_id
    end

    test "prevents duplicate links", %{scope: scope, workspace: w, provider: p} do
      manager = agent_fixture(scope, w.id, p.id)
      worker = agent_fixture(scope, w.id, p.id, %{role: :worker})

      {:ok, _} =
        Agents.link_agents(scope, %{
          manager_id: manager.id,
          worker_id: worker.id,
          pattern: :delegate
        })

      assert {:error, changeset} =
               Agents.link_agents(scope, %{
                 manager_id: manager.id,
                 worker_id: worker.id,
                 pattern: :handoff
               })

      assert "has already been taken" in errors_on(changeset).manager_id
    end
  end

  describe "unlink_agents/3" do
    setup :create_context

    test "removes a link", %{scope: scope, workspace: w, provider: p} do
      manager = agent_fixture(scope, w.id, p.id)
      worker = agent_fixture(scope, w.id, p.id, %{role: :worker})

      {:ok, _} =
        Agents.link_agents(scope, %{
          manager_id: manager.id,
          worker_id: worker.id,
          pattern: :delegate
        })

      assert {:ok, %AgentLink{}} = Agents.unlink_agents(scope, manager.id, worker.id)
      assert Agents.list_linked_workers(scope, manager.id) == []
    end

    test "returns error when link does not exist", %{scope: scope, workspace: w, provider: p} do
      f1 = agent_fixture(scope, w.id, p.id)
      f2 = agent_fixture(scope, w.id, p.id)
      assert {:error, :not_found} = Agents.unlink_agents(scope, f1.id, f2.id)
    end
  end

  describe "list_linked_workers/2" do
    setup :create_context

    test "returns linked workers", %{scope: scope, workspace: w, provider: p} do
      manager = agent_fixture(scope, w.id, p.id)
      worker1 = agent_fixture(scope, w.id, p.id, %{role: :worker})
      worker2 = agent_fixture(scope, w.id, p.id, %{role: :worker})

      {:ok, _} =
        Agents.link_agents(scope, %{
          manager_id: manager.id,
          worker_id: worker1.id,
          pattern: :delegate
        })

      {:ok, _} =
        Agents.link_agents(scope, %{
          manager_id: manager.id,
          worker_id: worker2.id,
          pattern: :handoff
        })

      workers = Agents.list_linked_workers(scope, manager.id)
      worker_ids = Enum.map(workers, & &1.id) |> Enum.sort()
      assert worker_ids == Enum.sort([worker1.id, worker2.id])
    end
  end
end
