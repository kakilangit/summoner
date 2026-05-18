defmodule Summoner.IntegrationTest do
  @moduledoc """
  End-to-end integration tests exercising the full application stack.
  """
  use Summoner.DataCase

  import Mox

  alias Summoner.Accounts
  alias Summoner.AccountsFixtures
  alias Summoner.Agents
  alias Summoner.Audit
  alias Summoner.Conversations
  alias Summoner.Ledger
  alias Summoner.Orchestration
  alias Summoner.Providers
  alias Summoner.Workspaces

  import Summoner.TenantsFixtures

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    user = AccountsFixtures.user_fixture()
    scope = Accounts.Scope.for_user(user)
    %{user: user, scope: scope}
  end

  describe "full conversation flow" do
    test "user creates workspace, provider, agent, conversation, sends message", %{
      scope: scope
    } do
      # 1. Create workspace
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "My Workspace"})
      assert workspace.name == "My Workspace"

      # 2. Add provider
      {:ok, provider} =
        Providers.create_provider(scope, %{
          name: "Local Ollama",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: workspace.id
        })

      assert provider.kind == "ollama"

      # 3. Create agent
      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "Assistant",
          model: "llama3",
          role: :autonomous,
          workspace_id: workspace.id,
          provider_id: provider.id,
          system_prompt: "You are a helpful assistant."
        })

      assert agent.name == "Assistant"

      # 4. Start conversation
      {:ok, conversation} =
        Conversations.create_conversation(scope, %{
          workspace_id: workspace.id,
          primary_agent_id: agent.id,
          title: "First Chat"
        })

      assert conversation.title == "First Chat"

      # 5. Add user message
      {:ok, user_msg} =
        Conversations.add_message(%{
          conversation_id: conversation.id,
          role: :user,
          content: "Hello, how are you?"
        })

      assert user_msg.role == :user

      # 6. Create invocation (simulating what the GenServer would do)
      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: workspace.id,
          agent_id: agent.id,
          conversation_id: conversation.id,
          input: %{"text" => "Hello, how are you?"}
        })

      assert invocation.status == :queued

      # 7. Simulate running and completing
      {:ok, invocation} =
        Orchestration.update_invocation_status(invocation, :running, %{
          started_at: DateTime.utc_now()
        })

      assert invocation.status == :running

      # 8. Add assistant response
      {:ok, assistant_msg} =
        Conversations.add_message(%{
          conversation_id: conversation.id,
          role: :assistant,
          content: "Hello! I'm doing well. How can I help you today?",
          agent_id: agent.id,
          invocation_id: invocation.id
        })

      assert assistant_msg.role == :assistant

      # 9. Complete invocation
      {:ok, invocation} =
        Orchestration.update_invocation_status(invocation, :completed, %{
          completed_at: DateTime.utc_now(),
          end_reason: :completed
        })

      assert invocation.status == :completed

      # 10. Verify message history
      messages = Conversations.list_messages(conversation.id, visibility: :public)
      assert length(messages) == 2
      assert Enum.at(messages, 0).role == :user
      assert Enum.at(messages, 1).role == :assistant
    end
  end

  describe "quota exceeded rejection flow" do
    test "invocation rejected when workspace quota exceeded", %{scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Quota WS"})

      # Set a very low quota
      workspace_with_settings =
        Workspaces.get_workspace!(scope, workspace.id)

      {:ok, _settings} =
        Workspaces.update_settings(scope, workspace_with_settings, %{
          token_quota_monthly: 1
        })

      {:ok, provider} =
        Providers.create_provider(scope, %{
          name: "Provider",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: workspace.id
        })

      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "Agent",
          model: "llama3",
          role: :autonomous,
          workspace_id: workspace.id,
          provider_id: provider.id
        })

      # Create a conversation and message with token usage to exceed quota
      {:ok, conversation} =
        Conversations.create_conversation(scope, %{
          workspace_id: workspace.id,
          primary_agent_id: agent.id,
          title: "Quota Test"
        })

      {:ok, _msg} =
        Conversations.add_message(%{
          conversation_id: conversation.id,
          role: :assistant,
          content: "response",
          token_count: 100
        })

      # Create invocation
      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: workspace.id,
          agent_id: agent.id,
          conversation_id: conversation.id,
          input: %{"text" => "test"}
        })

      # Check quota — should be exceeded now
      assert {:error, :quota_exceeded, %{usage: _, quota: 1}} =
               Ledger.check_workspace_quota(workspace.id)

      # Log an audit event for the rejection
      {:ok, log} =
        Audit.log(%{
          workspace_id: workspace.id,
          action: "quota_exceeded",
          detail: %{
            invocation_id: invocation.id,
            reason: "Monthly token quota exceeded"
          }
        })

      assert log.action == "quota_exceeded"

      # Verify audit log is recorded
      logs = Audit.list_logs(workspace.id)
      assert logs != []
      assert Enum.any?(logs, fn l -> l.action == "quota_exceeded" end)
    end
  end

  describe "invocation cancellation" do
    test "cancelled invocation is marked as cancelled", %{scope: scope} do
      tenant = tenant_fixture(scope)
      {:ok, workspace} = Workspaces.create_workspace(scope, tenant.id, %{name: "Cancel WS"})

      {:ok, provider} =
        Providers.create_provider(scope, %{
          name: "Provider",
          kind: "ollama",
          api_format: :openai,
          type: :local,
          base_url: "http://localhost:11434",
          workspace_id: workspace.id
        })

      {:ok, agent} =
        Agents.create_agent(scope, %{
          name: "Agent",
          model: "llama3",
          role: :autonomous,
          workspace_id: workspace.id,
          provider_id: provider.id
        })

      {:ok, invocation} =
        Orchestration.create_invocation(scope, %{
          workspace_id: workspace.id,
          agent_id: agent.id,
          conversation_id: nil,
          input: %{"text" => "test"}
        })

      # Move to running
      {:ok, invocation} =
        Orchestration.update_invocation_status(invocation, :running, %{
          started_at: DateTime.utc_now()
        })

      # Cancel directly via orchestration (simulating what server cancel does)
      {:ok, invocation} =
        Orchestration.update_invocation_status(invocation, :cancelled, %{
          completed_at: DateTime.utc_now(),
          end_reason: :cancelled
        })

      assert invocation.status == :cancelled
      assert invocation.end_reason == :cancelled

      # Verify the invocation remains cancelled
      reloaded = Orchestration.get_invocation_by_id(invocation.id)
      assert reloaded.status == :cancelled
    end
  end
end
