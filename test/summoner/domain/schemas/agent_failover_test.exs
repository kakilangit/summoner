defmodule Summoner.Domain.Schemas.AgentFailoverTest do
  use Summoner.DataCase, async: true

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.AgentFailoverEntry

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

  describe "AgentFailoverEntry changeset" do
    setup :create_context

    test "rejects self as backup", %{scope: scope, workspace: ws, provider: p} do
      agent = agent_fixture(scope, ws.id, p.id)

      changeset =
        AgentFailoverEntry.changeset(%AgentFailoverEntry{}, %{
          agent_id: agent.id,
          backup_agent_id: agent.id,
          position: 0
        })

      assert {"cannot back up itself", _} = changeset.errors[:backup_agent_id]
    end

    test "accepts a different agent as backup", %{scope: scope, workspace: ws, provider: p} do
      agent = agent_fixture(scope, ws.id, p.id)
      backup = agent_fixture(scope, ws.id, p.id, %{name: "Backup"})

      changeset =
        AgentFailoverEntry.changeset(%AgentFailoverEntry{}, %{
          agent_id: agent.id,
          backup_agent_id: backup.id,
          position: 0
        })

      refute changeset.errors[:backup_agent_id]
    end

    test "requires agent_id, backup_agent_id, and position" do
      changeset = AgentFailoverEntry.changeset(%AgentFailoverEntry{}, %{})

      assert changeset.errors[:agent_id]
      assert changeset.errors[:backup_agent_id]
      assert changeset.errors[:position]
    end

    test "rejects negative position" do
      scope = user_scope_fixture()
      ws = workspace_fixture(scope)
      p = provider_fixture(scope, ws.id)
      agent = agent_fixture(scope, ws.id, p.id)
      backup = agent_fixture(scope, ws.id, p.id, %{name: "Backup"})

      changeset =
        AgentFailoverEntry.changeset(%AgentFailoverEntry{}, %{
          agent_id: agent.id,
          backup_agent_id: backup.id,
          position: -1
        })

      assert changeset.errors[:position]
    end

    test "accepts valid position values", %{scope: scope, workspace: ws, provider: p} do
      agent = agent_fixture(scope, ws.id, p.id)
      backup = agent_fixture(scope, ws.id, p.id, %{name: "Backup"})

      for pos <- [0, 1, 5, 9] do
        changeset =
          AgentFailoverEntry.changeset(%AgentFailoverEntry{}, %{
            agent_id: agent.id,
            backup_agent_id: backup.id,
            position: pos
          })

        refute changeset.errors[:position]
      end
    end
  end

  describe "Agent changeset failover settings" do
    setup :create_context

    test "validates failover_delay_ms is non-negative", %{workspace: ws} do
      changeset =
        Agent.changeset(%Agent{}, %{
          name: "Test",
          role: :autonomous,
          workspace_id: ws.id,
          failover_delay_ms: -1
        })

      assert {"must be greater than or equal to %{number}",
              [validation: :number, kind: :greater_than_or_equal_to, number: 0]} =
               changeset.errors[:failover_delay_ms]
    end

    test "validates max_failover_depth range", %{workspace: ws} do
      changeset =
        Agent.changeset(%Agent{}, %{
          name: "Test",
          role: :autonomous,
          workspace_id: ws.id,
          max_failover_depth: 0
        })

      assert changeset.errors[:max_failover_depth]

      changeset =
        Agent.changeset(%Agent{}, %{
          name: "Test",
          role: :autonomous,
          workspace_id: ws.id,
          max_failover_depth: 11
        })

      assert changeset.errors[:max_failover_depth]
    end

    test "accepts valid failover settings", %{workspace: ws} do
      changeset =
        Agent.changeset(%Agent{}, %{
          name: "Test",
          role: :autonomous,
          workspace_id: ws.id,
          failover_strategy: :notify_then_auto,
          failover_delay_ms: 5000,
          max_failover_depth: 5
        })

      refute changeset.errors[:failover_strategy]
      refute changeset.errors[:failover_delay_ms]
      refute changeset.errors[:max_failover_depth]
    end
  end

  describe "Agent failover_chain association" do
    setup :create_context

    test "agent has_many failover_chain", %{scope: scope, workspace: ws, provider: p} do
      agent = agent_fixture(scope, ws.id, p.id)
      agent = Summoner.Repo.preload(agent, :failover_chain)

      assert agent.failover_chain == []
    end
  end
end
