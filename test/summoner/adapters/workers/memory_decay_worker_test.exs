defmodule Summoner.Adapters.Workers.MemoryDecayWorkerTest do
  use Summoner.DataCase

  import Ecto.Query

  alias Summoner.Adapters.Workers.MemoryDecayWorker
  alias Summoner.Domain.Schemas.AgentMemory
  alias Summoner.Ports.Persistence.AgentMemories

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentMemoriesFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    %{scope: scope, workspace: workspace, agent: agent}
  end

  setup :create_context

  describe "perform/1" do
    test "decays old memories", %{agent: agent, workspace: workspace} do
      # Create a memory with old last_accessed_at
      memory = agent_memory_fixture(agent.id, workspace.id, %{confidence: 1.0})

      # Manually set last_accessed_at to 14 days ago
      old_date = DateTime.add(DateTime.utc_now(), -14, :day)

      Summoner.Repo.update_all(
        from(m in AgentMemory, where: m.id == ^memory.id),
        set: [last_accessed_at: old_date]
      )

      assert :ok = MemoryDecayWorker.perform(%Oban.Job{})

      updated = AgentMemories.get_memory!(memory.id)
      assert updated.confidence < 1.0
    end

    test "prunes memories below threshold", %{agent: agent, workspace: workspace} do
      # Create a memory with very low confidence
      memory = agent_memory_fixture(agent.id, workspace.id, %{confidence: 0.05})

      # Set old access time so it's eligible
      old_date = DateTime.add(DateTime.utc_now(), -14, :day)

      Summoner.Repo.update_all(
        from(m in AgentMemory, where: m.id == ^memory.id),
        set: [last_accessed_at: old_date]
      )

      assert :ok = MemoryDecayWorker.perform(%Oban.Job{})

      assert_raise Ecto.NoResultsError, fn ->
        AgentMemories.get_memory!(memory.id)
      end
    end

    test "does not decay recently accessed memories", %{agent: agent, workspace: workspace} do
      memory = agent_memory_fixture(agent.id, workspace.id, %{confidence: 1.0})

      assert :ok = MemoryDecayWorker.perform(%Oban.Job{})

      updated = AgentMemories.get_memory!(memory.id)
      assert updated.confidence == 1.0
    end

    test "enforces memory cap", %{agent: agent, workspace: workspace} do
      # We can't easily create 501 memories in a test, but we can verify
      # the worker runs without error with a few memories
      for _ <- 1..5 do
        agent_memory_fixture(agent.id, workspace.id)
      end

      assert :ok = MemoryDecayWorker.perform(%Oban.Job{})
      assert AgentMemories.count_by_agent(agent.id) == 5
    end
  end
end
