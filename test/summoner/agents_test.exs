defmodule Summoner.Adapters.Persistence.AgentsTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Pipelines
  alias Summoner.Adapters.Persistence.Swarms
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.AgentLink

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

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
      assert f.local_agent.max_concurrent_invocations == 1
      assert f.local_agent.max_steps == 10
      assert f.local_agent.max_tokens_per_invocation == 50_000
    end

    test "creates a worker agent", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs = valid_agent_attributes(w.id, p.id, %{role: :worker})
      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.role == :worker
      assert f.local_agent.max_concurrent_invocations == 1
    end

    test "allows explicit max_concurrent_invocations", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs =
        valid_agent_attributes(w.id, p.id, %{max_concurrent_invocations: 5})

      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.local_agent.max_concurrent_invocations == 5
    end

    test "keeps default max_concurrent_invocations=1 for workers", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      attrs = valid_agent_attributes(w.id, p.id, %{role: :worker})
      assert {:ok, %Agent{} = f} = Agents.create_agent(scope, attrs)
      assert f.local_agent.max_concurrent_invocations == 1
    end

    test "requires mandatory fields", %{scope: scope} do
      assert {:error, changeset} = Agents.create_agent(scope, %{})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:workspace_id]
    end

    test "auto-generates unique callname when name conflicts", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      first = agent_fixture(scope, w.id, p.id, %{name: "dupe"})
      assert first.callname == "dupe"

      attrs = valid_agent_attributes(w.id, p.id, %{name: "dupe"})
      assert {:ok, second} = Agents.create_agent(scope, attrs)
      assert second.callname == "dupe_2"

      attrs3 = valid_agent_attributes(w.id, p.id, %{name: "dupe"})
      assert {:ok, third} = Agents.create_agent(scope, attrs3)
      assert third.callname == "dupe_3"
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

    test "cascade-removes pipeline stages", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)

      {:ok, pipeline} =
        Pipelines.create_pipeline(scope, %{
          name: "test-pipeline",
          workspace_id: w.id
        })

      {:ok, _stage} =
        Pipelines.add_stage(scope, %{
          pipeline_id: pipeline.id,
          agent_id: agent.id,
          position: 0,
          instruction: "do something"
        })

      assert {:ok, _} = Agents.delete_agent(scope, agent)
      assert [] = Pipelines.list_stages(pipeline.id)
    end

    test "cascade-removes swarm members", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id)

      {:ok, swarm} =
        Swarms.create_swarm(scope, %{
          name: "test-swarm",
          workspace_id: w.id
        })

      {:ok, _member} =
        Swarms.add_member(scope, %{
          swarm_id: swarm.id,
          agent_id: agent.id
        })

      assert {:ok, _} = Agents.delete_agent(scope, agent)
      assert [] = Swarms.list_members(swarm.id)
    end

    test "get_agent_with_provider! raises for deleted agent", %{
      scope: scope,
      workspace: w,
      provider: p
    } do
      agent = agent_fixture(scope, w.id, p.id)
      assert {:ok, _} = Agents.delete_agent(scope, agent)

      assert_raise Ecto.NoResultsError, fn ->
        Agents.get_agent_with_provider!(agent.id)
      end
    end

    test "deleted agent callname can be reused", %{scope: scope, workspace: w, provider: p} do
      agent = agent_fixture(scope, w.id, p.id, %{name: "reusable"})
      assert agent.callname == "reusable"
      assert {:ok, _} = Agents.delete_agent(scope, agent)

      new_agent = agent_fixture(scope, w.id, p.id, %{name: "reusable"})
      assert new_agent.callname == "reusable"
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
