defmodule Summoner.MemoryTest do
  use Summoner.DataCase

  alias Arcanum.Intent
  alias Summoner.Conversations
  alias Summoner.Memory

  import Summoner.AccountsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)

    agent =
      agent_fixture(scope, workspace.id, provider.id,
        system_prompt: "You are a helpful assistant.",
        personality: "Concise and formal."
      )

    conversation =
      Summoner.ConversationsFixtures.conversation_fixture(scope, workspace.id, agent.id)

    %{scope: scope, workspace: workspace, agent: agent, conversation: conversation}
  end

  # -------------------------------------------------------------------
  # build_system_prompt/1
  # -------------------------------------------------------------------

  describe "build_system_prompt/1" do
    setup :create_context

    test "combines personality and system_prompt", %{agent: fam} do
      result = Memory.build_system_prompt(fam, nil, harness: "")
      assert result.role == :system
      assert result.content == Intent.text("Concise and formal.\n\nYou are a helpful assistant.")
    end

    test "handles nil personality" do
      agent = %{system_prompt: "Instructions here.", personality: nil}
      result = Memory.build_system_prompt(agent, nil, harness: "")
      assert result.content == Intent.text("Instructions here.")
    end

    test "handles nil system_prompt" do
      agent = %{system_prompt: nil, personality: "Be friendly."}
      result = Memory.build_system_prompt(agent, nil, harness: "")
      assert result.content == Intent.text("Be friendly.")
    end

    test "handles both nil" do
      agent = %{system_prompt: nil, personality: nil}
      result = Memory.build_system_prompt(agent, nil, harness: "")
      assert result.content == Intent.text("")
    end

    test "prepends harness when provided" do
      agent = %{system_prompt: "Do the thing.", personality: nil}
      result = Memory.build_system_prompt(agent, nil, harness: "## Rules\nBe safe.")
      assert result.content == Intent.text("## Rules\nBe safe.\n\nDo the thing.")
    end

    test "uses default harness from presets when harness is nil" do
      agent = %{system_prompt: "Hello.", personality: nil}
      result = Memory.build_system_prompt(agent)
      assert Intent.to_text(result.content) =~ "Operational Guidelines"
      assert Intent.to_text(result.content) =~ "Hello."
    end
  end

  # -------------------------------------------------------------------
  # assemble_context/4
  # -------------------------------------------------------------------

  describe "assemble_context/4" do
    setup :create_context

    test "assembles in correct order: system, history, new message", %{
      agent: fam,
      conversation: conv
    } do
      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "previous question"
        })

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "previous answer"
        })

      context = Memory.assemble_context(conv.id, fam, "new question")

      assert [system, hist_user, hist_assistant, new_user] = context
      assert system.role == :system
      assert Intent.to_text(system.content) =~ "Concise and formal."
      assert Intent.to_text(system.content) =~ "You are a helpful assistant."
      assert hist_user == %{role: :user, content: Intent.text("previous question")}
      assert hist_assistant == %{role: :assistant, content: Intent.text("previous answer")}
      assert new_user == %{role: :user, content: Intent.text("new question")}
    end

    test "injects skill instructions after system prompt", %{agent: fam, conversation: conv} do
      skills = ["Always cite sources.", "Use formal language."]
      context = Memory.assemble_context(conv.id, fam, "hello", skills: skills)

      assert [system, skill1, skill2, new_user] = context
      assert system.role == :system
      assert skill1 == %{role: :system, content: Intent.text("Always cite sources.")}
      assert skill2 == %{role: :system, content: Intent.text("Use formal language.")}
      assert new_user.role == :user
    end

    test "injects tool definitions after skills", %{agent: fam, conversation: conv} do
      tools = [%{"name" => "search", "description" => "Search the web"}]
      skills = ["Be helpful."]

      context = Memory.assemble_context(conv.id, fam, "hello", skills: skills, tools: tools)

      assert [_system, skill, tool_msg, new_user] = context
      assert skill.content == Intent.text("Be helpful.")
      assert tool_msg.role == :system
      assert Intent.to_text(tool_msg.content) =~ "Available tools:"
      assert Intent.to_text(tool_msg.content) =~ "search"
      assert new_user.role == :user
    end

    test "respects context_window limit", %{agent: fam, conversation: conv} do
      for i <- 1..10 do
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "msg #{i}"
        })
      end

      context = Memory.assemble_context(conv.id, fam, "new", context_window: 3)

      # system + 3 history + new message = 5
      assert length(context) == 5
      # History should be the 3 most recent
      [_system, h1, h2, h3, _new] = context
      assert h1.content == Intent.text("msg 8")
      assert h2.content == Intent.text("msg 9")
      assert h3.content == Intent.text("msg 10")
    end

    test "handles empty history", %{agent: fam, conversation: conv} do
      context = Memory.assemble_context(conv.id, fam, "first message")

      assert [system, new_user] = context
      assert system.role == :system
      assert new_user == %{role: :user, content: Intent.text("first message")}
    end

    test "preserves tool_call_id on tool messages", %{agent: fam, conversation: conv} do
      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :tool,
          content: ~s({"result": "ok"}),
          tool_call_id: "call_123"
        })

      context = Memory.assemble_context(conv.id, fam, "next")

      [_system, tool_msg, _new] = context
      assert tool_msg.role == :tool
      assert tool_msg.tool_call_id == "call_123"
    end

    test "preserves tool_calls on assistant messages", %{agent: fam, conversation: conv} do
      tool_calls = [
        %{
          "id" => "call_1",
          "type" => "function",
          "function" => %{"name" => "search", "arguments" => "{}"}
        }
      ]

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "",
          tool_calls: tool_calls
        })

      context = Memory.assemble_context(conv.id, fam, "next")

      [_system, assistant_msg, _tool_error, _new] = context
      assert assistant_msg.tool_calls == tool_calls
    end

    test "only loads public messages for history", %{agent: fam, conversation: conv} do
      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
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

      context = Memory.assemble_context(conv.id, fam, "new")

      # system + 1 public history + new = 3 (internal excluded)
      assert length(context) == 3
      [_system, hist, _new] = context
      assert hist.content == Intent.text("public msg")
    end
  end
end
