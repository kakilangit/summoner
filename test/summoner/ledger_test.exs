defmodule Summoner.Adapters.Persistence.LedgerTest do
  use Summoner.DataCase

  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Ledger
  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.Message
  alias Summoner.Repo

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.ConversationsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.OrchestrationFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    conversation = conversation_fixture(scope, workspace.id, agent.id)

    %{
      scope: scope,
      workspace: workspace,
      agent: agent,
      conversation: conversation
    }
  end

  defp add_message_with_tokens(conversation_id, token_count) do
    {:ok, _} =
      Conversations.add_message(%{
        conversation_id: conversation_id,
        role: :assistant,
        content: "response",
        token_count: token_count
      })
  end

  # -------------------------------------------------------------------
  # check_workspace_quota/1
  # -------------------------------------------------------------------

  describe "check_workspace_quota/1" do
    setup :create_context

    test "returns :ok when quota is unlimited (null)", %{workspace: ws} do
      assert :ok = Ledger.check_workspace_quota(ws.id)
    end

    test "returns :ok when under quota", %{scope: scope, workspace: ws, conversation: conv} do
      {:ok, _} = Workspaces.update_settings(scope, ws, %{token_quota_monthly: 10_000})
      add_message_with_tokens(conv.id, 5_000)

      assert :ok = Ledger.check_workspace_quota(ws.id)
    end

    test "returns error when at quota", %{scope: scope, workspace: ws, conversation: conv} do
      {:ok, _} = Workspaces.update_settings(scope, ws, %{token_quota_monthly: 10_000})
      add_message_with_tokens(conv.id, 10_000)

      assert {:error, :quota_exceeded, %{usage: 10_000, quota: 10_000}} =
               Ledger.check_workspace_quota(ws.id)
    end

    test "returns error when over quota", %{scope: scope, workspace: ws, conversation: conv} do
      {:ok, _} = Workspaces.update_settings(scope, ws, %{token_quota_monthly: 10_000})
      add_message_with_tokens(conv.id, 7_000)
      add_message_with_tokens(conv.id, 5_000)

      assert {:error, :quota_exceeded, %{usage: 12_000, quota: 10_000}} =
               Ledger.check_workspace_quota(ws.id)
    end

    test "ignores messages with null token_count", %{
      scope: scope,
      workspace: ws,
      conversation: conv
    } do
      {:ok, _} = Workspaces.update_settings(scope, ws, %{token_quota_monthly: 10_000})
      add_message_with_tokens(conv.id, 5_000)

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          role: :user,
          content: "no tokens"
        })

      assert :ok = Ledger.check_workspace_quota(ws.id)
    end

    test "ignores messages older than 30 days", %{scope: scope, workspace: ws, conversation: conv} do
      {:ok, _} = Workspaces.update_settings(scope, ws, %{token_quota_monthly: 10_000})

      # Add a recent message under quota
      add_message_with_tokens(conv.id, 5_000)

      # Manually insert an old message via Repo to backdate it
      old_date = DateTime.utc_now() |> DateTime.add(-31, :day)

      %Message{}
      |> Message.changeset(%{
        conversation_id: conv.id,
        role: :assistant,
        content: "old",
        token_count: 20_000
      })
      |> Repo.insert!()
      |> Ecto.Changeset.change(inserted_at: old_date)
      |> Repo.update!()

      assert :ok = Ledger.check_workspace_quota(ws.id)
    end
  end

  # -------------------------------------------------------------------
  # check_invocation_cap/2
  # -------------------------------------------------------------------

  describe "check_invocation_cap/2" do
    setup :create_context

    test "returns :ok when under cap", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      inv = invocation_fixture(scope, ws.id, fam.id, conversation_id: conv.id)

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          invocation_id: inv.id,
          role: :assistant,
          content: "response",
          token_count: 1_000
        })

      assert :ok = Ledger.check_invocation_cap(inv.id, 50_000)
    end

    test "returns error when at cap", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      inv = invocation_fixture(scope, ws.id, fam.id, conversation_id: conv.id)

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: conv.id,
          invocation_id: inv.id,
          role: :assistant,
          content: "response",
          token_count: 50_000
        })

      assert {:error, :token_limit_reached, %{usage: 50_000, cap: 50_000}} =
               Ledger.check_invocation_cap(inv.id, 50_000)
    end

    test "returns error when over cap", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      inv = invocation_fixture(scope, ws.id, fam.id, conversation_id: conv.id)

      for _ <- 1..3 do
        Conversations.add_message(%{
          conversation_id: conv.id,
          invocation_id: inv.id,
          role: :assistant,
          content: "response",
          token_count: 20_000
        })
      end

      assert {:error, :token_limit_reached, %{usage: 60_000, cap: 50_000}} =
               Ledger.check_invocation_cap(inv.id, 50_000)
    end

    test "returns :ok when no messages exist", %{scope: scope, workspace: ws, agent: fam} do
      inv = invocation_fixture(scope, ws.id, fam.id)
      assert :ok = Ledger.check_invocation_cap(inv.id, 50_000)
    end
  end

  # -------------------------------------------------------------------
  # estimate_tokens/1
  # -------------------------------------------------------------------

  describe "estimate_tokens/1" do
    test "returns 0 for nil" do
      assert Ledger.estimate_tokens(nil) == 0
    end

    test "returns 0 for empty string" do
      assert Ledger.estimate_tokens("") == 0
    end

    test "estimates tokens as character count / 4" do
      # 20 chars → 5 tokens
      assert Ledger.estimate_tokens("12345678901234567890") == 5
    end

    test "returns at least 1 for short strings" do
      assert Ledger.estimate_tokens("hi") == 1
    end

    test "handles longer content" do
      content = String.duplicate("a", 400)
      assert Ledger.estimate_tokens(content) == 100
    end
  end

  # -------------------------------------------------------------------
  # estimate_message_tokens/1
  # -------------------------------------------------------------------

  describe "estimate_message_tokens/1" do
    test "estimates tokens for a simple user message" do
      msg = %{role: :user, content: "Hello world"}
      tokens = Ledger.estimate_message_tokens(msg)
      # base(4) + content("Hello world" = 11 chars / 4 = 2, min 1 → 2)
      assert tokens > 0
    end

    test "includes tool_calls in estimate" do
      tool_calls = [%{id: "tc_1", function: %{name: "read", arguments: "{}"}}]
      msg = %{role: :assistant, content: "Let me read that", tool_calls: tool_calls}
      without = %{role: :assistant, content: "Let me read that"}

      assert Ledger.estimate_message_tokens(msg) > Ledger.estimate_message_tokens(without)
    end

    test "includes tool_call_id in estimate" do
      msg = %{role: :tool, content: "file contents here", tool_call_id: "tc_abc123"}
      without = %{role: :tool, content: "file contents here"}

      assert Ledger.estimate_message_tokens(msg) > Ledger.estimate_message_tokens(without)
    end

    test "includes thinking in estimate" do
      msg = %{role: :assistant, content: "answer", thinking: "let me reason about this carefully"}
      without = %{role: :assistant, content: "answer"}

      assert Ledger.estimate_message_tokens(msg) > Ledger.estimate_message_tokens(without)
    end
  end

  # -------------------------------------------------------------------
  # estimate_context_tokens/1
  # -------------------------------------------------------------------

  describe "estimate_context_tokens/1" do
    test "sums tokens across all messages" do
      messages = [
        %{role: :system, content: "You are helpful"},
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi there"}
      ]

      total = Ledger.estimate_context_tokens(messages)
      individual_sum = Enum.reduce(messages, 0, &(Ledger.estimate_message_tokens(&1) + &2))
      assert total == individual_sum
    end

    test "returns 0 for empty list" do
      assert Ledger.estimate_context_tokens([]) == 0
    end
  end
end
