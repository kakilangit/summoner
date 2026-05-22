defmodule Summoner.Services.Memory.PartySharingTest do
  use Summoner.DataCase

  alias Summoner.Ports.Persistence.AgentMemories
  alias Summoner.Ports.Persistence.Swarms
  alias Summoner.Services.Memory.PartySharing

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AgentMemoriesFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  defp create_party(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent_a = agent_fixture(scope, workspace.id, provider.id)
    agent_b = agent_fixture(scope, workspace.id, provider.id)

    # Create a swarm with both agents
    {:ok, swarm} =
      Swarms.create_swarm(scope, %{
        name: "test-party",
        workspace_id: workspace.id,
        mode: :round_robin,
        max_turns: 10
      })

    {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent_a.id})
    {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent_b.id})

    %{
      scope: scope,
      workspace: workspace,
      agent_a: agent_a,
      agent_b: agent_b,
      swarm: swarm
    }
  end

  describe "share_memory/1" do
    setup :create_party

    test "shares fact memories to party peers", %{
      agent_a: agent_a,
      agent_b: agent_b,
      workspace: workspace
    } do
      memory = agent_memory_fixture(agent_a.id, workspace.id, %{type: :fact})

      assert :ok = PartySharing.share_memory(memory)

      peer_memories = AgentMemories.list_by_agent(agent_b.id)
      assert length(peer_memories) == 1
      [shared] = peer_memories
      assert shared.content == memory.content
      assert shared.type == :fact
      assert_in_delta shared.confidence, 0.7, 0.01
    end

    test "shares procedure memories to party peers", %{
      agent_a: agent_a,
      agent_b: agent_b,
      workspace: workspace
    } do
      memory = agent_memory_fixture(agent_a.id, workspace.id, %{type: :procedure})

      assert :ok = PartySharing.share_memory(memory)

      peer_memories = AgentMemories.list_by_agent(agent_b.id)
      assert length(peer_memories) == 1
    end

    test "does not share preference memories", %{
      agent_a: agent_a,
      agent_b: agent_b,
      workspace: workspace
    } do
      memory = agent_memory_fixture(agent_a.id, workspace.id, %{type: :preference})

      assert :ok = PartySharing.share_memory(memory)

      assert AgentMemories.list_by_agent(agent_b.id) == []
    end

    test "does not share correction memories", %{
      agent_a: agent_a,
      agent_b: agent_b,
      workspace: workspace
    } do
      memory = agent_memory_fixture(agent_a.id, workspace.id, %{type: :correction})

      assert :ok = PartySharing.share_memory(memory)

      assert AgentMemories.list_by_agent(agent_b.id) == []
    end

    test "skips duplicates", %{
      agent_a: agent_a,
      agent_b: agent_b,
      workspace: workspace
    } do
      # Pre-create identical memory on agent_b
      content = "The sky is blue"
      agent_memory_fixture(agent_b.id, workspace.id, %{content: content})

      memory = agent_memory_fixture(agent_a.id, workspace.id, %{content: content})

      assert :ok = PartySharing.share_memory(memory)

      # agent_b should still have only 1 memory (no duplicate)
      assert length(AgentMemories.list_by_agent(agent_b.id)) == 1
    end

    test "shares to agents not in any party", %{agent_a: agent_a, workspace: workspace} do
      # Agent not in any swarm - should still work (no-op)
      scope = user_scope_fixture()
      provider = provider_fixture(scope, workspace.id)
      loner = agent_fixture(scope, workspace.id, provider.id)

      memory = agent_memory_fixture(loner.id, workspace.id, %{type: :fact})

      assert :ok = PartySharing.share_memory(memory)

      # agent_a should not receive anything (loner has no peers)
      original_count = length(AgentMemories.list_by_agent(agent_a.id))
      assert original_count == 0
    end
  end
end
