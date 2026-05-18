defmodule Summoner.SwarmsTest do
  use Summoner.DataCase

  alias Summoner.Swarms
  alias Summoner.Swarms.Swarm

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.SwarmsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)

    %{scope: scope, workspace: workspace, provider: provider, agent: agent}
  end

  describe "create_swarm/2" do
    setup :create_context

    test "creates a swarm", %{scope: scope, workspace: ws} do
      {:ok, swarm} =
        Swarms.create_swarm(scope, %{name: "Test Party", workspace_id: ws.id})

      assert swarm.name == "Test Party"
      assert swarm.workspace_id == ws.id
      assert swarm.mode == :relay
      assert swarm.max_turns == 20
    end

    test "creates a swarm with mode and settings", %{scope: scope, workspace: ws} do
      {:ok, swarm} =
        Swarms.create_swarm(scope, %{
          name: "RR Party",
          workspace_id: ws.id,
          mode: :round_robin,
          max_turns: 10
        })

      assert swarm.mode == :round_robin
      assert swarm.max_turns == 10
    end

    test "directed mode requires coordinator", %{scope: scope, workspace: ws} do
      {:error, changeset} =
        Swarms.create_swarm(scope, %{
          name: "Auto Party",
          workspace_id: ws.id,
          mode: :directed
        })

      assert errors_on(changeset).coordinator_agent_id
    end

    test "directed mode succeeds with coordinator", %{
      scope: scope,
      workspace: ws,
      agent: agent
    } do
      {:ok, swarm} =
        Swarms.create_swarm(scope, %{
          name: "Auto Party",
          workspace_id: ws.id,
          mode: :directed,
          coordinator_agent_id: agent.id
        })

      assert swarm.mode == :directed
      assert swarm.coordinator_agent_id == agent.id
    end

    test "rejects duplicate name in same workspace", %{scope: scope, workspace: ws} do
      {:ok, _} = Swarms.create_swarm(scope, %{name: "Dupe", workspace_id: ws.id})
      {:error, changeset} = Swarms.create_swarm(scope, %{name: "Dupe", workspace_id: ws.id})

      assert errors_on(changeset).workspace_id
    end

    test "validates max_turns bounds", %{scope: scope, workspace: ws} do
      {:error, changeset} =
        Swarms.create_swarm(scope, %{name: "Bad", workspace_id: ws.id, max_turns: 0})

      assert errors_on(changeset).max_turns

      {:error, changeset} =
        Swarms.create_swarm(scope, %{name: "Bad", workspace_id: ws.id, max_turns: 101})

      assert errors_on(changeset).max_turns
    end
  end

  describe "list_swarms/2" do
    setup :create_context

    test "lists swarms for workspace", %{scope: scope, workspace: ws} do
      swarm_fixture(scope, ws.id, %{name: "Alpha"})
      swarm_fixture(scope, ws.id, %{name: "Beta"})

      swarms = Swarms.list_swarms(scope, ws.id)
      assert length(swarms) == 2
      assert Enum.map(swarms, & &1.name) == ["Alpha", "Beta"]
    end
  end

  describe "add_member/2 and remove_member/2" do
    setup :create_context

    test "adds and removes a member", %{scope: scope, workspace: ws, agent: agent} do
      swarm = swarm_fixture(scope, ws.id)

      {:ok, member} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent.id})
      assert member.swarm_id == swarm.id
      assert member.agent_id == agent.id

      members = Swarms.list_members(swarm.id)
      assert length(members) == 1

      {:ok, _} = Swarms.remove_member(scope, member)
      assert Swarms.list_members(swarm.id) == []
    end

    test "rejects duplicate member", %{scope: scope, workspace: ws, agent: agent} do
      swarm = swarm_fixture(scope, ws.id)

      {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent.id})
      {:error, changeset} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent.id})

      assert errors_on(changeset).swarm_id
    end
  end

  describe "delete_swarm/2" do
    setup :create_context

    test "deletes swarm and its members", %{scope: scope, workspace: ws, agent: agent} do
      swarm = swarm_fixture(scope, ws.id)
      {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent.id})

      {:ok, _} = Swarms.delete_swarm(scope, swarm)

      assert Swarms.list_swarms(scope, ws.id) == []
    end
  end

  describe "create_conversation/2" do
    setup :create_context

    test "creates a conversation linked to swarm with participants", %{
      scope: scope,
      workspace: ws,
      provider: provider,
      agent: agent
    } do
      agent2 = agent_fixture(scope, ws.id, provider.id, %{name: "Agent Two"})
      swarm = swarm_fixture(scope, ws.id)
      {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent.id})
      {:ok, _} = Swarms.add_member(scope, %{swarm_id: swarm.id, agent_id: agent2.id})

      # Reload swarm with members
      swarm = Swarms.get_swarm!(scope, ws.id, swarm.id)

      {:ok, conversation} = Swarms.create_conversation(scope, swarm)

      assert conversation.swarm_id == swarm.id
      assert conversation.workspace_id == ws.id
      assert conversation.title == "#{swarm.name} Channel"

      participants = Summoner.Conversations.list_participants(conversation.id)
      assert length(participants) == 2
    end

    test "returns error when swarm has no members", %{scope: scope, workspace: ws} do
      swarm = swarm_fixture(scope, ws.id)
      swarm = Swarms.get_swarm!(scope, ws.id, swarm.id)

      assert {:error, :no_members} = Swarms.create_conversation(scope, swarm)
    end
  end

  describe "Swarm changeset" do
    test "mode defaults to :relay" do
      changeset = Swarm.changeset(%Swarm{}, %{name: "Test", workspace_id: Nulid.generate()})
      assert Ecto.Changeset.get_field(changeset, :mode) == :relay
    end

    test "max_turns defaults to 20" do
      changeset = Swarm.changeset(%Swarm{}, %{name: "Test", workspace_id: Nulid.generate()})
      assert Ecto.Changeset.get_field(changeset, :max_turns) == 20
    end

    test "rejects invalid mode" do
      changeset =
        Swarm.changeset(%Swarm{}, %{
          name: "Test",
          workspace_id: Nulid.generate(),
          mode: :invalid
        })

      assert changeset.errors[:mode]
    end
  end
end
