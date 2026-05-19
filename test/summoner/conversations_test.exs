defmodule Summoner.Adapters.Persistence.ConversationsTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Domain.Types.Content

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.ConversationsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    %{scope: scope, workspace: workspace, provider: provider, agent: agent}
  end

  # -------------------------------------------------------------------
  # Conversations CRUD
  # -------------------------------------------------------------------

  describe "create_conversation/2" do
    setup :create_context

    test "creates a conversation with valid attrs", %{scope: scope, workspace: ws, agent: fam} do
      {:ok, conversation} =
        Conversations.create_conversation(scope, %{
          workspace_id: ws.id,
          primary_agent_id: fam.id,
          title: "Test Chat"
        })

      assert conversation.title == "Test Chat"
      assert conversation.workspace_id == ws.id
      assert conversation.primary_agent_id == fam.id
      assert conversation.user_id == scope.user.id
    end

    test "auto-adds the primary agent as participant", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      {:ok, conversation} =
        Conversations.create_conversation(scope, %{
          workspace_id: ws.id,
          primary_agent_id: fam.id
        })

      participants = Conversations.list_participants(conversation.id)
      assert length(participants) == 1
      assert hd(participants).agent_id == fam.id
    end

    test "fails without required fields", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Conversations.create_conversation(scope, %{})
    end
  end

  describe "list_conversations/2" do
    setup :create_context

    test "returns conversations for workspace ordered by most recent", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      c1 = conversation_fixture(scope, ws.id, fam.id, title: "First")
      c2 = conversation_fixture(scope, ws.id, fam.id, title: "Second")

      result = Conversations.list_conversations(scope, ws.id)
      assert [%{id: id2}, %{id: id1}] = result
      assert id1 == c1.id
      assert id2 == c2.id
    end

    test "does not return conversations from other workspaces", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      _conv = conversation_fixture(scope, ws.id, fam.id)

      other_ws = workspace_fixture(scope, name: "other-ws")
      other_provider = provider_fixture(scope, other_ws.id)
      other_fam = agent_fixture(scope, other_ws.id, other_provider.id)
      _other_conv = conversation_fixture(scope, other_ws.id, other_fam.id)

      result = Conversations.list_conversations(scope, ws.id)
      assert length(result) == 1
    end
  end

  describe "get_conversation!/3" do
    setup :create_context

    test "returns conversation scoped to workspace", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)
      found = Conversations.get_conversation!(scope, ws.id, conv.id)
      assert found.id == conv.id
    end

    test "raises when conversation is in different workspace", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      conv = conversation_fixture(scope, ws.id, fam.id)

      other_ws = workspace_fixture(scope, name: "other-ws")

      assert_raise Ecto.NoResultsError, fn ->
        Conversations.get_conversation!(scope, other_ws.id, conv.id)
      end
    end
  end

  describe "update_primary_agent/3" do
    setup :create_context

    test "changes the primary agent", %{
      scope: scope,
      workspace: ws,
      provider: prov,
      agent: fam
    } do
      conv = conversation_fixture(scope, ws.id, fam.id)
      new_fam = agent_fixture(scope, ws.id, prov.id, name: "new-agent")

      {:ok, updated} = Conversations.update_primary_agent(scope, conv, new_fam.id)
      assert updated.primary_agent_id == new_fam.id
    end
  end

  # -------------------------------------------------------------------
  # Participants
  # -------------------------------------------------------------------

  describe "add_participant/2" do
    setup :create_context

    test "adds a new participant", %{scope: scope, workspace: ws, provider: prov, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)
      new_fam = agent_fixture(scope, ws.id, prov.id, name: "worker")

      {:ok, participant} = Conversations.add_participant(conv.id, new_fam.id)
      assert participant.conversation_id == conv.id
      assert participant.agent_id == new_fam.id
      assert participant.joined_at
    end

    test "rejects duplicate participant", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      # Primary agent is already a participant from create_conversation
      assert {:error, %Ecto.Changeset{}} = Conversations.add_participant(conv.id, fam.id)
    end
  end

  describe "list_participants/1" do
    setup :create_context

    test "returns participants ordered by joined_at", %{
      scope: scope,
      workspace: ws,
      provider: prov,
      agent: fam
    } do
      conv = conversation_fixture(scope, ws.id, fam.id)
      fam2 = agent_fixture(scope, ws.id, prov.id, name: "second")
      {:ok, _} = Conversations.add_participant(conv.id, fam2.id)

      participants = Conversations.list_participants(conv.id)
      assert length(participants) == 2
      assert hd(participants).agent_id == fam.id
    end
  end

  # -------------------------------------------------------------------
  # Messages
  # -------------------------------------------------------------------

  describe "add_message/1" do
    setup :create_context

    test "creates a message with required fields", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, message} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "Hello!",
          visibility: :public,
          kind: :chat
        })

      assert message.role == :user
      assert message.content == Content.from_string("Hello!")
      assert message.visibility == :public
      assert message.kind == :chat
    end

    test "creates an assistant message with agent_id", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, message} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          agent_id: fam.id,
          content: "Hi there!",
          token_count: 42
        })

      assert message.role == :assistant
      assert message.agent_id == fam.id
      assert message.token_count == 42
    end

    test "creates a tool message with tool_call_id", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, message} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :tool,
          content: ~s({"result": "ok"}),
          tool_call_id: "call_abc123",
          visibility: :internal
        })

      assert message.role == :tool
      assert message.tool_call_id == "call_abc123"
      assert message.visibility == :internal
    end

    test "creates an assistant message with tool_calls", %{
      scope: scope,
      workspace: ws,
      agent: fam
    } do
      conv = conversation_fixture(scope, ws.id, fam.id)

      tool_calls = [
        %{
          "id" => "call_1",
          "type" => "function",
          "function" => %{"name" => "search", "arguments" => "{}"}
        }
      ]

      {:ok, message} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          agent_id: fam.id,
          tool_calls: tool_calls
        })

      assert message.tool_calls == tool_calls
    end

    test "fails without conversation_id", %{} do
      assert {:error, %Ecto.Changeset{}} =
               Conversations.add_message(%{role: :user, content: "hi"})
    end
  end

  describe "list_messages/2" do
    setup :create_context

    test "returns messages in chronological order", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, m1} =
        Conversations.add_message(%{conversation_id: conv.id, role: :user, content: "first"})

      {:ok, m2} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "second"
        })

      messages = Conversations.list_messages(conv.id)
      assert [%{id: id1}, %{id: id2}] = messages
      assert id1 == m1.id
      assert id2 == m2.id
    end

    test "respects limit option", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      for i <- 1..5 do
        Conversations.add_message(%{conversation_id: conv.id, role: :user, content: "msg #{i}"})
      end

      messages = Conversations.list_messages(conv.id, limit: 3)
      assert length(messages) == 3
      # Should return the 3 most recent in chronological order
      assert hd(messages).content == Content.from_string("msg 3")
    end

    test "filters by visibility", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "public",
          visibility: :public
        })

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "internal",
          visibility: :internal
        })

      public = Conversations.list_messages(conv.id, visibility: :public)
      assert length(public) == 1
      assert hd(public).content == Content.from_string("public")

      internal = Conversations.list_messages(conv.id, visibility: :internal)
      assert length(internal) == 1
      assert hd(internal).content == Content.from_string("internal")

      all = Conversations.list_messages(conv.id)
      assert length(all) == 2
    end
  end

  describe "delete_conversation/2" do
    setup :create_context

    test "deletes a conversation", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id, title: "Doomed")
      assert {:ok, _} = Conversations.delete_conversation(scope, conv)

      assert_raise Ecto.NoResultsError, fn ->
        Conversations.get_conversation!(scope, ws.id, conv.id)
      end
    end

    test "cascades messages and participants", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Conversations.add_message(%{conversation_id: conv.id, role: :user, content: "hi"})

      assert {:ok, _} = Conversations.delete_conversation(scope, conv)

      assert Conversations.list_messages(conv.id) == []
      assert Conversations.list_participants(conv.id) == []
    end
  end

  # -------------------------------------------------------------------
  # Export
  # -------------------------------------------------------------------

  describe "export_as_markdown/2" do
    setup :create_context

    test "exports messages as markdown", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Conversations.add_message(%{conversation_id: conv.id, role: :user, content: "Hello"})

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          agent_id: fam.id,
          content: "Hi there"
        })

      md = Conversations.export_as_markdown(conv.id, title: "Test Channel")

      assert md =~ "# Test Channel"
      assert md =~ "**User**"
      assert md =~ "Hello"
      assert md =~ "Hi there"
    end

    test "excludes deleted and compacted messages", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Conversations.add_message(%{conversation_id: conv.id, role: :user, content: "visible"})

      {:ok, msg2} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "deleted"
        })

      {:ok, msg3} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "compacted"
        })

      Conversations.soft_delete_message(msg2)
      Conversations.mark_compacted([msg3.id])

      md = Conversations.export_as_markdown(conv.id)

      assert md =~ "visible"
      refute md =~ "deleted"
      refute md =~ "compacted"
    end

    test "excludes internal messages", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "public msg",
          visibility: :public
        })

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "internal msg",
          visibility: :internal
        })

      md = Conversations.export_as_markdown(conv.id)

      assert md =~ "public msg"
      refute md =~ "internal msg"
    end

    test "returns header only when no messages", %{scope: scope, workspace: ws, agent: fam} do
      conv = conversation_fixture(scope, ws.id, fam.id)
      md = Conversations.export_as_markdown(conv.id, title: "Empty")

      assert md == "# Empty\n\n"
    end
  end
end
