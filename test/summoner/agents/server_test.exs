defmodule Summoner.Agents.ServerTest do
  use Summoner.DataCase

  import Mox

  alias Arcanum.{Intent, Response}
  alias Summoner.Agents.Server

  import Summoner.AccountsFixtures
  import Summoner.ConversationsFixtures
  import Summoner.AgentsFixtures
  import Summoner.ProvidersFixtures
  import Summoner.WorkspacesFixtures

  setup :set_mox_global
  setup :verify_on_exit!

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)

    agent =
      agent_fixture(scope, workspace.id, provider.id,
        system_prompt: "You are helpful.",
        max_concurrent_invocations: 1
      )

    conversation = conversation_fixture(scope, workspace.id, agent.id)

    %{
      scope: scope,
      workspace: workspace,
      provider: provider,
      agent: agent,
      conversation: conversation
    }
  end

  defp start_server(agent, opts \\ []) do
    start_supervised!(
      {Server,
       [
         agent_id: agent.id,
         workspace_id: agent.workspace_id,
         adapter: Summoner.InferenceAdapterMock,
         tool_executor: Keyword.get(opts, :tool_executor)
       ]
       |> Keyword.merge(opts)}
    )
  end

  defp stub_chat_response(content \\ "Hello!") do
    Summoner.InferenceAdapterMock
    |> expect(:stream, fn _provider, _intent, _profile ->
      {:ok,
       [
         {:data,
          %Response{
            content: Intent.text(content),
            tool_calls: nil,
            usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
            finish_reason: "stop"
          }},
         :done
       ]}
    end)
  end

  # -------------------------------------------------------------------
  # Invoke
  # -------------------------------------------------------------------

  describe "invoke/3" do
    setup :create_context

    test "accepts and runs an invocation", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      stub_chat_response()
      _pid = start_server(fam)

      {:ok, invocation} =
        Server.invoke(ws.id, fam.id, %{
          conversation_id: conv.id,
          message: "Hello",
          scope: scope
        })

      assert invocation.status == :completed
      assert invocation.agent_id == fam.id
    end

    test "queues when at concurrency limit and replies after completion", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      # First call blocks in the adapter
      test_pid = self()

      Summoner.InferenceAdapterMock
      |> expect(:stream, 2, fn _provider, _intent, _profile ->
        send(test_pid, :call_started)
        Process.sleep(200)

        {:ok,
         [
           {:data,
            %Response{
              content: Intent.text("Response"),
              tool_calls: nil,
              usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
              finish_reason: "stop"
            }},
           :done
         ]}
      end)

      _pid = start_server(fam)

      # First invoke — runs immediately
      {:ok, _inv1} =
        Server.invoke(ws.id, fam.id, %{
          conversation_id: conv.id,
          message: "First",
          scope: scope
        })

      # Wait for the first task to actually start
      assert_receive :call_started, 1_000

      # Second invoke in a task — blocks until dequeued and completed
      task =
        Task.async(fn ->
          Server.invoke(ws.id, fam.id, %{
            conversation_id: conv.id,
            message: "Second",
            scope: scope
          })
        end)

      # Wait for the dequeued invocation to also start
      assert_receive :call_started, 2_000

      # The second invoke should return with a completed invocation
      {:ok, inv2} = Task.await(task, 5_000)
      assert inv2.status == :completed
    end
  end

  # -------------------------------------------------------------------
  # Registry
  # -------------------------------------------------------------------

  describe "alive?/2" do
    setup :create_context

    test "returns true when server is running", %{agent: fam} do
      _pid = start_server(fam)
      assert Server.alive?(fam.workspace_id, fam.id)
    end

    test "returns false when server is not running", %{agent: fam} do
      refute Server.alive?(fam.workspace_id, fam.id)
    end
  end

  # -------------------------------------------------------------------
  # Cancellation
  # -------------------------------------------------------------------

  describe "cancel/3" do
    setup :create_context

    test "marks invocation for cancellation", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      Summoner.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        Process.sleep(300)

        {:ok,
         [
           {:data,
            %Response{
              content: Intent.text("done"),
              tool_calls: nil,
              usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
              finish_reason: "stop"
            }},
           :done
         ]}
      end)

      _pid = start_server(fam)

      {:ok, invocation} =
        Server.invoke(ws.id, fam.id, %{
          conversation_id: conv.id,
          message: "Hello",
          scope: scope
        })

      # Cancel is a cast — doesn't block
      :ok = Server.cancel(ws.id, fam.id, invocation.id)

      # Wait for completion
      Process.sleep(500)
    end
  end

  # -------------------------------------------------------------------
  # Quota exceeded
  # -------------------------------------------------------------------

  describe "invoke/3 quota exceeded" do
    setup :create_context

    test "rejects invocation when workspace quota exceeded", %{
      scope: scope,
      workspace: ws,
      agent: fam,
      conversation: conv
    } do
      # Set a very low quota
      {:ok, _} = Summoner.Workspaces.update_settings(scope, ws, %{token_quota_monthly: 1})

      # Add a message that exceeds the quota
      {:ok, _} =
        Summoner.Conversations.add_message(%{
          conversation_id: conv.id,
          role: :assistant,
          content: "used up",
          token_count: 100
        })

      _pid = start_server(fam)

      {:error, :quota_exceeded} =
        Server.invoke(ws.id, fam.id, %{
          conversation_id: conv.id,
          message: "Hello",
          scope: scope
        })
    end
  end
end
