defmodule Summoner.Services.Orchestration.ReactLoopTest do
  use Summoner.DataCase

  import Mox

  alias Arcanum.{Intent, Response}
  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Domain.Types.Content
  alias Summoner.Services.Orchestration.ReactLoop

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.ConversationsFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.OrchestrationFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup :verify_on_exit!

  # Wraps a Response into a stream enumerable matching adapter.stream/2 return format.
  defp stream_response(%Response{} = response) do
    {:ok, [{:data, response}, :done]}
  end

  defp create_context(_ctx) do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)

    agent =
      agent_fixture(scope, workspace.id, provider.id,
        system_prompt: "You are helpful.",
        max_steps: 5,
        step_timeout_s: 5,
        total_timeout_s: 30
      )

    conversation = conversation_fixture(scope, workspace.id, agent.id)

    invocation =
      invocation_fixture(scope, workspace.id, agent.id, conversation_id: conversation.id)

    context = [
      %{role: :system, content: "You are helpful."},
      %{role: :user, content: "Hello"}
    ]

    %{
      scope: scope,
      workspace: workspace,
      provider: provider,
      agent: agent,
      conversation: conversation,
      invocation: invocation,
      context: context
    }
  end

  # -------------------------------------------------------------------
  # Happy path — no tools
  # -------------------------------------------------------------------

  describe "run/5 happy path (no tools)" do
    setup :create_context

    test "completes with a direct response", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text("Hello! How can I help?"),
          tool_calls: nil,
          usage: %{prompt_tokens: 10, completion_tokens: 8, total_tokens: 18},
          finish_reason: "stop"
        })
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx, adapter: Summoner.Services.InferenceAdapterMock)

      assert completed.status == :completed
      assert completed.end_reason == :completed
      assert completed.output == %{"response" => "Hello! How can I help?"}

      # Verify step was recorded
      steps = Orchestration.list_steps(inv.id)
      assert length(steps) == 1
      assert hd(steps).reasoning == "Hello! How can I help?"

      # Verify final message was written to conversation
      messages = Conversations.list_messages(completed.conversation_id)
      assistant_msg = Enum.find(messages, &(&1.role == :assistant))

      assert assistant_msg.content ==
               Content.from_string("Hello! How can I help?")

      assert assistant_msg.token_count == 18

      # Verify completion event
      events = Orchestration.list_events(inv.id)
      assert Enum.any?(events, &(&1.event_type == :completed))
    end
  end

  # -------------------------------------------------------------------
  # Single tool call
  # -------------------------------------------------------------------

  describe "run/5 with tool call" do
    setup :create_context

    test "executes tool and completes", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      # First call returns a tool call
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "search", arguments: ~s({"query": "elixir"})}}
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      # Second call returns final response after tool result
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text("Elixir is a functional language."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
          finish_reason: "stop"
        })
      end)

      Summoner.ToolExecutorMock
      |> expect(:execute, fn tool_call, _agent_id ->
        assert tool_call.function.name == "search"
        {:ok, "Elixir is a dynamic, functional language."}
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock
        )

      assert completed.status == :completed

      # 2 steps: tool call + final response
      steps = Orchestration.list_steps(inv.id)
      assert length(steps) == 2
      assert hd(steps).tool_name == "search"

      # Verify tool events
      events = Orchestration.list_events(inv.id)
      assert Enum.any?(events, &(&1.event_type == :tool_started))
      assert Enum.any?(events, &(&1.event_type == :tool_finished))
    end
  end

  # -------------------------------------------------------------------
  # Tool error + retry
  # -------------------------------------------------------------------

  describe "run/5 tool error and retry" do
    setup :create_context

    test "retries once on tool failure then succeeds", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "flaky_tool", arguments: "{}"}}
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text("Done with retry."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 5, total_tokens: 25},
          finish_reason: "stop"
        })
      end)

      # First call fails, retry succeeds
      Summoner.ToolExecutorMock
      |> expect(:execute, fn _tool_call, _agent_id ->
        {:error, "connection timeout"}
      end)
      |> expect(:execute, fn _tool_call, _agent_id ->
        {:ok, "retry succeeded"}
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock
        )

      assert completed.status == :completed

      events = Orchestration.list_events(inv.id)
      assert Enum.any?(events, &(&1.event_type == :tool_failed))
      assert Enum.any?(events, &(&1.event_type == :completed))
    end
  end

  # -------------------------------------------------------------------
  # Max steps reached
  # -------------------------------------------------------------------

  describe "run/5 max steps" do
    setup :create_context

    test "stops at max_steps", %{
      scope: scope,
      workspace: ws,
      provider: prov,
      conversation: conv,
      context: ctx
    } do
      # Create agent with max_steps: 2
      agent =
        agent_fixture(scope, ws.id, prov.id,
          name: "limited",
          max_steps: 2,
          system_prompt: "test"
        )

      inv = invocation_fixture(scope, ws.id, agent.id, conversation_id: conv.id)

      # Both calls return tool calls, so we'll hit max_steps
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, 2, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{
              id: "call_#{System.unique_integer([:positive])}",
              function: %{name: "search", arguments: "{}"}
            }
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)

      Summoner.ToolExecutorMock
      |> expect(:execute, 2, fn _tool_call, _agent_id ->
        {:ok, "result"}
      end)

      {:ok, completed} =
        ReactLoop.run(agent, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock
        )

      assert completed.status == :completed
      assert completed.end_reason == :step_limit_reached
    end
  end

  # -------------------------------------------------------------------
  # Inference failure
  # -------------------------------------------------------------------

  describe "run/5 inference failure" do
    setup :create_context

    test "fails when inference call errors", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        {:error, {:http, 500, "Internal Server Error"}}
      end)

      {:error, :failed, failed} =
        ReactLoop.run(fam, prov, inv, ctx, adapter: Summoner.Services.InferenceAdapterMock)

      assert failed.status == :failed
      assert failed.end_reason == :failed
    end
  end

  # -------------------------------------------------------------------
  # Worker visibility
  # -------------------------------------------------------------------

  describe "run/5 worker visibility" do
    setup :create_context

    test "worker agents write internal messages", %{
      scope: scope,
      workspace: ws,
      provider: prov,
      conversation: conv,
      context: ctx
    } do
      worker =
        agent_fixture(scope, ws.id, prov.id,
          name: "worker",
          role: :worker,
          system_prompt: "worker prompt"
        )

      inv = invocation_fixture(scope, ws.id, worker.id, conversation_id: conv.id, depth: 1)

      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text("worker output"),
          tool_calls: nil,
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "stop"
        })
      end)

      {:ok, _} =
        ReactLoop.run(worker, prov, inv, ctx, adapter: Summoner.Services.InferenceAdapterMock)

      messages = Conversations.list_messages(conv.id, visibility: :internal)
      assert length(messages) == 1
      assert hd(messages).content == Content.from_string("worker output")
    end
  end

  # -------------------------------------------------------------------
  # Token estimation fallback
  # -------------------------------------------------------------------

  describe "run/5 token estimation" do
    setup :create_context

    test "uses estimate when provider returns no usage", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text(String.duplicate("a", 100)),
          tool_calls: nil,
          usage: nil,
          finish_reason: "stop"
        })
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx, adapter: Summoner.Services.InferenceAdapterMock)

      assert completed.status == :completed

      # Message should have estimated token count (100 chars / 4 = 25)
      messages = Conversations.list_messages(completed.conversation_id)
      assistant_msg = Enum.find(messages, &(&1.role == :assistant))
      assert assistant_msg.token_count == 25
    end
  end

  # -------------------------------------------------------------------
  # Tool output truncation
  # -------------------------------------------------------------------

  describe "run/5 tool output truncation" do
    setup :create_context

    test "truncates tool output exceeding max_tool_output_chars", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      large_output = String.duplicate("x", 500)

      # First call returns a tool call
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "read_file", arguments: ~s({"path": "/big"})}}
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      # Second call — verify the tool result was truncated in context
      |> expect(:stream, fn _provider, intent, _profile ->
        tool_msg = Enum.find(intent.messages, &(&1.role == :tool))
        assert tool_msg != nil
        tool_text = Intent.to_text(tool_msg.content)
        assert String.contains?(tool_text, "[OUTPUT TRUNCATED")
        assert String.contains?(tool_text, "100 of 500 characters")
        # Content before truncation marker should be exactly 100 chars
        [before_marker | _] = String.split(tool_text, "\n\n[OUTPUT TRUNCATED")
        assert String.length(before_marker) == 100

        stream_response(%Response{
          content: Intent.text("Done."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 5, total_tokens: 25},
          finish_reason: "stop"
        })
      end)

      Summoner.ToolExecutorMock
      |> expect(:execute, fn _tool_call, _agent_id ->
        {:ok, large_output}
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock,
          max_tool_output_chars: 100
        )

      assert completed.status == :completed
    end

    test "does not truncate tool output within limit", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      small_output = "short result"

      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "search", arguments: ~s({"q": "x"})}}
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      |> expect(:stream, fn _provider, intent, _profile ->
        tool_msg = Enum.find(intent.messages, &(&1.role == :tool))
        assert tool_msg.content == Intent.text("short result")
        refute String.contains?(Intent.to_text(tool_msg.content), "[OUTPUT TRUNCATED")

        stream_response(%Response{
          content: Intent.text("Done."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 5, total_tokens: 25},
          finish_reason: "stop"
        })
      end)

      Summoner.ToolExecutorMock
      |> expect(:execute, fn _tool_call, _agent_id ->
        {:ok, small_output}
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock,
          max_tool_output_chars: 100
        )

      assert completed.status == :completed
    end
  end

  # -------------------------------------------------------------------
  # Context budget enforcement
  # -------------------------------------------------------------------

  describe "run/5 context budget enforcement" do
    setup :create_context

    test "evicts old messages when context exceeds budget", %{
      scope: scope,
      workspace: ws,
      conversation: conv,
      context: _ctx
    } do
      # Create provider with tiny context_length to trigger eviction
      provider = provider_fixture(scope, ws.id, %{name: "tiny-ctx"})

      agent =
        agent_fixture(scope, ws.id, provider.id,
          name: "budget-test",
          system_prompt: "sys",
          max_steps: 5,
          context_length: 200
        )

      inv = invocation_fixture(scope, ws.id, agent.id, conversation_id: conv.id)

      # Build a context that will exceed 200 * 0.8 = 160 token budget
      # Each message ~base(4) + content tokens
      big_content = String.duplicate("x", 800)

      context = [
        %{role: :system, content: "sys"},
        %{role: :user, content: "first question"},
        %{role: :assistant, content: big_content},
        %{role: :tool, content: big_content, tool_call_id: "tc_1"},
        %{role: :user, content: "second question"}
      ]

      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, intent, _profile ->
        # The old big messages should have been evicted
        # System + last user msg should remain
        msg_count = length(intent.messages)
        assert msg_count < 5

        # System prompt must be preserved
        assert hd(intent.messages).role == :system

        # Last user message must be preserved
        assert List.last(intent.messages).role == :user

        stream_response(%Response{
          content: Intent.text("Done."),
          tool_calls: nil,
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "stop"
        })
      end)

      {:ok, completed} =
        ReactLoop.run(agent, provider, inv, context,
          adapter: Summoner.Services.InferenceAdapterMock
        )

      assert completed.status == :completed
    end

    test "does not evict when context is within budget", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      # Default provider has nil context_length → 131K budget
      # Small context should not trigger eviction
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, intent, _profile ->
        # All messages should be preserved
        assert length(intent.messages) == length(ctx)

        stream_response(%Response{
          content: Intent.text("All good."),
          tool_calls: nil,
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "stop"
        })
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx, adapter: Summoner.Services.InferenceAdapterMock)

      assert completed.status == :completed
    end
  end

  # -------------------------------------------------------------------
  # Tool call param validation — missing required params
  # -------------------------------------------------------------------

  describe "run/5 tool call with missing required params" do
    setup :create_context

    test "filters tool calls with missing required params and recovers", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      tools = [
        %{
          type: "function",
          function: %{
            name: "bash",
            description: "Run a shell command",
            parameters: %{
              "type" => "object",
              "properties" => %{
                "command" => %{"type" => "string"}
              },
              "required" => ["command"]
            }
          }
        }
      ]

      # First call: LLM returns bash with empty args (missing required "command")
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "bash", arguments: "{}"}}
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      # Second call: LLM recovers with a proper response
      |> expect(:stream, fn _provider, intent, _profile ->
        # Verify the error message was fed back
        tool_msg = Enum.find(intent.messages, &(&1.role == :tool))
        assert tool_msg != nil
        tool_text = Intent.to_text(tool_msg.content)
        assert String.contains?(tool_text, "missing required parameter")
        assert String.contains?(tool_text, "command")

        stream_response(%Response{
          content: Intent.text("I apologize, let me try differently."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
          finish_reason: "stop"
        })
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tools: tools
        )

      assert completed.status == :completed
    end

    test "filters only invalid calls, executes valid ones", %{
      agent: fam,
      provider: prov,
      invocation: inv,
      context: ctx
    } do
      tools = [
        %{
          type: "function",
          function: %{
            name: "bash",
            description: "Run a shell command",
            parameters: %{
              "type" => "object",
              "properties" => %{
                "command" => %{"type" => "string"}
              },
              "required" => ["command"]
            }
          }
        },
        %{
          type: "function",
          function: %{
            name: "search",
            description: "Search for something",
            parameters: %{
              "type" => "object",
              "properties" => %{
                "query" => %{"type" => "string"}
              },
              "required" => ["query"]
            }
          }
        }
      ]

      # LLM returns two tool calls: one valid, one missing required param
      Summoner.Services.InferenceAdapterMock
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: nil,
          tool_calls: [
            %{id: "call_1", function: %{name: "bash", arguments: "{}"}},
            %{
              id: "call_2",
              function: %{name: "search", arguments: ~s({"query": "elixir"})}
            }
          ],
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          finish_reason: "tool_calls"
        })
      end)
      |> expect(:stream, fn _provider, _intent, _profile ->
        stream_response(%Response{
          content: Intent.text("Found results."),
          tool_calls: nil,
          usage: %{prompt_tokens: 20, completion_tokens: 5, total_tokens: 25},
          finish_reason: "stop"
        })
      end)

      # Only search should be executed (bash is filtered out)
      Summoner.ToolExecutorMock
      |> expect(:execute, fn tool_call, _agent_id ->
        assert tool_call.function.name == "search"
        {:ok, "Elixir is great"}
      end)

      {:ok, completed} =
        ReactLoop.run(fam, prov, inv, ctx,
          adapter: Summoner.Services.InferenceAdapterMock,
          tool_executor: Summoner.ToolExecutorMock,
          tools: tools
        )

      assert completed.status == :completed
    end
  end
end
