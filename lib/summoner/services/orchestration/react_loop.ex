defmodule Summoner.Services.Orchestration.ReactLoop do
  @moduledoc """
  The ReAct (Reasoning + Action) loop — core agent execution engine.

  Executes a cycle of: send context to provider → parse response →
  if tool_call, execute tool → record step → loop until done or
  limits reached.

  ## Limits

  - **max_steps** — configurable per Agent (default 10)
  - **step_timeout** — per-tool-call timeout (default 60s)
  - **total_timeout** — total invocation timeout (default 300s)
  - **token cap** — per-invocation token limit

  ## Error Policy

  On tool error, retry the same tool once. After 2 consecutive failures
  on the same tool, terminate with an error summary.
  """

  require Logger

  alias Arcanum.{Intent, ModelProfile, Response}
  alias Arcanum.Response.Normalizer
  alias Summoner.Domain.Events.ContentToken
  alias Summoner.Domain.Policies.Failover, as: FailoverPolicy
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Ports.Events
  alias Summoner.Ports.Harness
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Ledger
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Ports.Workers
  alias Summoner.Services.Agents.Server, as: AgentServer
  alias Summoner.Services.EventLog
  alias Summoner.Services.Inference
  alias Summoner.Services.Orchestration.AgentFailover
  alias Summoner.Services.Orchestration.ApprovalGate
  alias Summoner.Services.Orchestration.BuiltinTools
  alias Summoner.Services.Orchestration.ToolCallRecovery

  @doc """
  Runs the ReAct loop for an invocation.

  ## Parameters

  - `agent` — the Agent struct (with provider preloaded)
  - `provider` — the Provider struct
  - `invocation` — the Invocation struct
  - `context` — initial context (list of message maps from Memory)
  - `opts`:
    - `:tool_executor` — module implementing `ToolExecutor` behaviour

  ## Returns

  - `{:ok, invocation}` — completed successfully
  - `{:error, reason, invocation}` — failed with reason
  """
  @complete_tool_name "__complete__"
  @done_tool_name "__done__"
  @relay_tool_name "__relay__"
  @doom_loop_threshold 3
  @default_max_tool_output_chars 32_000
  @default_context_length 131_072
  @completion_reserve_ratio 0.20

  @complete_tool_def %{
    type: "function",
    function: %{
      name: @complete_tool_name,
      description:
        "Signal that your task is complete and return the final result. " <>
          "You MUST call this tool when you are finished with your assigned task. " <>
          "Do NOT simply write your answer as text — always use this tool to submit it.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "result" => %{
            "type" => "string",
            "description" => "The final result/output of your task"
          }
        },
        "required" => ["result"]
      }
    }
  }

  def run(agent, provider, invocation, context, opts \\ []) do
    tool_executor = Keyword.get(opts, :tool_executor)
    adapter_override = Keyword.get(opts, :adapter)
    tools = Keyword.get(opts, :tools)
    pipeline_stage? = Keyword.get(opts, :pipeline_stage, false)
    swarm? = Keyword.get(opts, :swarm, false)
    swarm_members = Keyword.get(opts, :swarm_members, [])
    swarm_mode = Keyword.get(opts, :swarm_mode)
    max_tool_output = Keyword.get(opts, :max_tool_output_chars, @default_max_tool_output_chars)
    max_tool_concurrency = Keyword.get(opts, :max_tool_concurrency, 1)

    context_length = agent.local_agent.context_length || @default_context_length
    context_budget = trunc(context_length * (1.0 - @completion_reserve_ratio))

    tools =
      inject_orchestration_tools(tools, pipeline_stage?, swarm?, swarm_mode, swarm_members, agent)

    context =
      inject_swarm_context_if_needed(context, agent, swarm?, swarm_members, swarm_mode)

    state = %{
      agent: agent,
      provider: provider,
      invocation: invocation,
      context: context,
      tool_executor: tool_executor,
      gateway_opts: if(adapter_override, do: [adapter: adapter_override], else: []),
      tools: tools,
      pipeline_stage: pipeline_stage?,
      swarm_mode: swarm_mode,
      swarm_members: swarm_members,
      max_tool_output_chars: max_tool_output,
      max_tool_concurrency: max_tool_concurrency,
      context_budget: context_budget,
      step_number: 0,
      token_count: 0,
      prompt_tokens: 0,
      completion_tokens: 0,
      has_real_usage: false,
      started_at: System.monotonic_time(:millisecond),
      consecutive_failures: %{},
      recent_tool_calls: [],
      relay_reprompted: false,
      complete_nudge_count: 0
    }

    {:ok, invocation} =
      Orchestration.update_invocation_status(invocation, :running, %{
        started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    state = %{state | invocation: invocation}
    loop(state)
  end

  # -------------------------------------------------------------------
  # Loop
  # -------------------------------------------------------------------

  defp loop(state) do
    cond do
      state.step_number >= state.agent.local_agent.max_steps ->
        output = last_tool_output(state.context)
        finish(state, :completed, :step_limit_reached, %{"response" => output})

      total_timeout_exceeded?(state) ->
        output = last_tool_output(state.context)
        add_timeout_message(state)
        finish(state, :completed, :total_timeout, %{"response" => output})

      true ->
        case check_token_cap(state) do
          :ok -> execute_step(state)
          {:error, :token_limit_reached, _} -> finish(state, :completed, :token_limit_reached)
        end
    end
  end

  defp execute_step(state) do
    state = enforce_context_budget(state)
    messages = maybe_append_mention_reminder(state)

    intent = %Intent{
      messages: messages,
      model: state.agent.local_agent.model,
      tools: state.tools,
      max_tokens: max_completion_tokens(state),
      context_length: state.agent.local_agent.context_length
    }

    case call_inference_with_retries(state, intent) do
      {:ok, %Response{} = response} ->
        state = track_tokens(state, response)
        handle_response(state, response)

      {:error, :context_overflow} ->
        Logger.warning("Context overflow detected, terminating invocation")
        finish(state, :failed, :context_overflow, %{"error" => "context_overflow"})

      {:error, {:api_error, _status, _body} = error} ->
        maybe_failover_or_finish(state, error)

      {:error, reason} ->
        maybe_failover_or_finish(state, reason)
    end
  end

  defp maybe_failover_or_finish(state, error) do
    chain = state.agent.failover_chain
    has_chain = is_list(chain) and chain != []

    if has_chain && FailoverPolicy.failover_eligible?(error) do
      Logger.warning("Inference failed with failover-eligible error: #{inspect(error)}")
      execute_failover(state, error)
    else
      message = format_inference_error(error)
      Logger.error("Inference call failed: #{message}")
      finish(state, :failed, :failed, %{"error" => message})
    end
  end

  defp execute_failover(state, error) do
    case AgentFailover.handle(state.agent, state.invocation, error) do
      {:failover, backup_agent, depth} ->
        invoke_backup(state, backup_agent, error, depth)

      {:failover_delayed, backup_agent, delay_ms, depth} ->
        Process.sleep(delay_ms)
        invoke_backup(state, backup_agent, error, depth)

      _ ->
        # No failover possible — finish as normal failure
        message = format_inference_error(error)
        Logger.error("Inference call failed (no failover): #{message}")
        finish(state, :failed, :failed, %{"error" => message})
    end
  end

  defp invoke_backup(state, backup_agent, _error, depth) do
    params = %{
      conversation_id: state.invocation.conversation_id,
      message: get_in(state.invocation.input, ["message"]),
      scope: %{user: nil},
      react_opts: %{},
      failover_depth: depth,
      failover_from_agent_id: state.agent.id,
      failover_reason: "failover from @#{state.agent.callname}"
    }

    case AgentServer.invoke(backup_agent.workspace_id, backup_agent.id, params) do
      {:ok, backup_invocation} ->
        # Return success — caller sees backup's result as the final outcome
        {:ok, backup_invocation}

      {:error, reason} ->
        # Backup also failed — finish as failure
        Logger.error("Backup agent @#{backup_agent.callname} also failed: #{inspect(reason)}")
        finish(state, :failed, :failed, %{"error" => "failover failed: #{inspect(reason)}"})
    end
  end

  defp format_inference_error({:api_error, status, body}) do
    "HTTP #{status} — #{format_api_error(status, body)}"
  end

  defp format_inference_error(reason) do
    format_error(reason)
  end

  defp call_inference_with_retries(state, intent, _attempt \\ 1) do
    # Retries are handled inside the adapter. No branching here.
    if state.invocation.conversation_id do
      call_streaming(state, intent)
    else
      Inference.Gateway.chat(state.provider, intent, state.gateway_opts)
    end
  end

  defp call_streaming(state, intent) do
    case Inference.Gateway.stream(state.provider, intent, state.gateway_opts) do
      {:ok, stream} ->
        merged = consume_stream(state, stream)
        # Recover swarm signal tool calls that lost their name during streaming
        merged = ToolCallRecovery.recover(merged)
        # Normalize the final merged response (XML tool-call extraction, etc.)
        profile =
          ModelProfile.Resolver.resolve(state.provider.kind, state.agent.local_agent.model)

        {:ok, Normalizer.normalize(merged, profile)}

      {:error, _reason} = error ->
        error
    end
  end

  defp consume_stream(state, stream) do
    workspace_id = state.invocation.workspace_id
    agent_id = state.agent.id
    invocation_id = state.invocation.id

    acc = %Response{content: nil, thinking: nil, tool_calls: nil, usage: nil, finish_reason: nil}

    Enum.reduce(stream, acc, fn
      {:data, %Response{} = delta}, acc ->
        # Broadcast content or thinking tokens to LiveView subscribers
        broadcast_token = Response.text(delta) || delta.thinking

        if broadcast_token && broadcast_token != "" do
          Events.publish(%ContentToken{
            workspace_id: workspace_id,
            agent_id: agent_id,
            invocation_id: invocation_id,
            token: broadcast_token
          })
        end

        merge_delta(acc, delta)

      :done, acc ->
        acc

      {:error, reason}, acc ->
        Logger.warning("Stream error mid-flight: #{inspect(reason)}")
        acc
    end)
  end

  defp merge_delta(acc, delta) do
    %Response{
      content: merge_content_blocks(acc.content, delta.content),
      thinking: merge_string(acc.thinking, delta.thinking),
      tool_calls: merge_tool_calls(acc.tool_calls, delta.tool_calls),
      usage: delta.usage || acc.usage,
      finish_reason: delta.finish_reason || acc.finish_reason
    }
  end

  defp merge_content_blocks(nil, nil), do: nil
  defp merge_content_blocks(nil, new) when is_list(new), do: new
  defp merge_content_blocks(acc, nil) when is_list(acc), do: acc

  defp merge_content_blocks(acc, new) when is_list(acc) and is_list(new) do
    # Coalesce consecutive text blocks so streaming tokens merge into one block
    Enum.reduce(new, acc, fn
      %{type: :text, text: new_text}, acc_list ->
        case List.last(acc_list) do
          %{type: :text, text: existing_text} ->
            List.replace_at(acc_list, -1, %{type: :text, text: existing_text <> new_text})

          _ ->
            acc_list ++ [%{type: :text, text: new_text}]
        end

      block, acc_list ->
        acc_list ++ [block]
    end)
  end

  defp merge_string(nil, nil), do: nil
  defp merge_string(nil, new) when is_binary(new), do: new
  defp merge_string(acc, nil) when is_binary(acc), do: acc
  defp merge_string(acc, new) when is_binary(acc) and is_binary(new), do: acc <> new

  defp merge_tool_calls(nil, nil), do: nil
  defp merge_tool_calls(nil, new) when is_list(new), do: new
  defp merge_tool_calls(acc, nil) when is_list(acc), do: acc

  defp merge_tool_calls(acc, new) when is_list(acc) and is_list(new) do
    # OpenAI streams tool_calls with `index` fields — merge by index.
    # Anthropic emits complete tool_calls in message_delta, so simple concat works.
    Enum.reduce(new, acc, fn tc, acc_list ->
      idx = Map.get(tc, :index) || Map.get(tc, "index")

      if idx do
        merge_tool_call_at_index(acc_list, idx, tc)
      else
        acc_list ++ [tc]
      end
    end)
  end

  defp merge_tool_call_at_index(acc_list, idx, tc) do
    if idx < length(acc_list) do
      List.update_at(acc_list, idx, &merge_single_tool_call(&1, tc))
    else
      # New tool call at this index — pad if needed
      padding =
        List.duplicate(%{id: nil, function: %{name: nil, arguments: ""}}, idx - length(acc_list))

      acc_list ++ padding ++ [normalize_tool_call(tc)]
    end
  end

  defp merge_single_tool_call(existing, delta) do
    ef = tc_function(existing)
    df = tc_function(delta)

    merged_args = (ef[:arguments] || "") <> (df[:arguments] || "")

    Logger.debug(
      "tool_call merge: name=#{inspect(ef[:name] || df[:name])} " <>
        "delta_args=#{inspect(df[:arguments])} merged_len=#{byte_size(merged_args)}"
    )

    %{
      id: tc_field(delta, :id) || tc_field(existing, :id),
      function: %{
        name: ef[:name] || df[:name],
        arguments: merged_args
      }
    }
  end

  defp normalize_tool_call(tc) do
    f = tc_function(tc)
    %{id: tc_field(tc, :id), function: %{name: f[:name], arguments: f[:arguments] || ""}}
  end

  # Extracts a field from a map that may use atom or string keys.
  defp tc_field(map, key), do: map[key] || map[to_string(key)]

  # Extracts the :function sub-map, normalizing keys to atoms.
  defp tc_function(tc) do
    f = tc[:function] || tc["function"] || %{}
    %{name: f[:name] || f["name"], arguments: f[:arguments] || f["arguments"]}
  end

  defp handle_response(state, %Response{tool_calls: tool_calls} = response)
       when is_list(tool_calls) and tool_calls != [] do
    state = %{state | step_number: state.step_number + 1}

    # Record the assistant message with tool calls in context
    assistant_msg =
      %{role: :assistant, content: response.content || [], tool_calls: tool_calls}
      |> maybe_add_thinking(response.thinking)

    state = %{state | context: state.context ++ [assistant_msg]}

    # Execute each tool call and collect results
    execute_tool_calls(state, tool_calls, response)
  end

  # No tool calls in response — final response or pipeline nudge
  defp handle_response(state, %Response{tool_calls: nil_or_empty} = response)
       when nil_or_empty in [nil, []] do
    do_handle_final_response(state, response)
  end

  @max_complete_nudges 2

  defp do_handle_final_response(%{pipeline_stage: true} = state, response) do
    content_text = Response.text(response) || last_tool_output(state.context)

    if state.complete_nudge_count >= @max_complete_nudges do
      # Agent failed to call __complete__ after multiple nudges — auto-complete
      Logger.warning(
        "Pipeline stage agent failed to call __complete__ after #{@max_complete_nudges} nudges, auto-completing"
      )

      state = %{state | step_number: state.step_number + 1}

      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: state.invocation.id,
          workspace_id: state.invocation.workspace_id,
          step_number: state.step_number,
          reasoning: content_text,
          tool_name: "__complete__",
          tool_input: %{"result" => content_text || ""},
          status: :ok
        })

      write_final_message(state, %Response{content: response.content, usage: response.usage})
      finish(state, :completed, :completed, %{"result" => content_text || ""})
    else
      # Nudge the agent to call __complete__
      Logger.warning("Pipeline stage agent responded without calling __complete__, nudging")

      state = %{
        state
        | step_number: state.step_number + 1,
          complete_nudge_count: state.complete_nudge_count + 1
      }

      # Record the text response as a step
      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: state.invocation.id,
          workspace_id: state.invocation.workspace_id,
          step_number: state.step_number,
          reasoning: content_text,
          status: :ok
        })

      # Add assistant message + system nudge to context
      nudge = %{
        role: :user,
        content:
          Intent.text(
            "You must call the __complete__ tool with your final result to finish this task. " <>
              "Do NOT respond with plain text. Use the __complete__ tool now."
          )
      }

      assistant_msg =
        %{role: :assistant, content: response.content || []}
        |> maybe_add_thinking(response.thinking)

      state = %{
        state
        | context:
            state.context ++
              [assistant_msg, nudge]
      }

      loop(state)
    end
  end

  defp do_handle_final_response(state, response) do
    # No tool calls — final response
    # In relay mode, the agent MUST call __relay__. If it didn't, re-prompt once.
    if state.swarm_mode == :relay and not relay_reprompted?(state) do
      handle_missing_relay(state, response)
    else
      do_handle_final_response_inner(state, response)
    end
  end

  # When a relay agent responds with text only (no __relay__ call), inject the
  # response into context and re-prompt with a nudge to call the tool.
  defp handle_missing_relay(state, response) do
    Logger.warning("Relay agent #{state.agent.callname} did not call __relay__, re-prompting")

    context =
      state.context ++
        [
          %{role: :assistant, content: response.content || []},
          %{
            role: :system,
            content:
              Intent.text(
                "You MUST call the __relay__ tool now. " <>
                  "If no other member can add value, use next_agent=\"__done__\" to finish."
              )
          }
        ]

    state = %{state | context: context, relay_reprompted: true}
    loop(state)
  end

  defp relay_reprompted?(%{relay_reprompted: true}), do: true
  defp relay_reprompted?(_), do: false

  defp do_handle_final_response_inner(state, response) do
    # No tool calls — final response
    state = %{state | step_number: state.step_number + 1}

    content_text = Response.text(response) || last_tool_output(state.context)

    # If model produced no content at all (e.g. all tool calls were malformed and filtered),
    # finish with :empty_response so the view layer can inform the user.
    if is_nil(content_text) or String.trim(content_text) == "" do
      Logger.warning("Model produced empty response (possible malformed tool calls filtered)")

      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: state.invocation.id,
          workspace_id: state.invocation.workspace_id,
          step_number: state.step_number,
          reasoning: nil,
          status: :ok
        })

      finish(state, :failed, :empty_response, %{"error" => "empty_response"})
    else
      # Record final step
      {:ok, _step} =
        Orchestration.add_step(%{
          invocation_id: state.invocation.id,
          workspace_id: state.invocation.workspace_id,
          step_number: state.step_number,
          reasoning: content_text,
          status: :ok
        })

      # Write final assistant message to conversation
      final_content = response.content || Intent.text(content_text)
      write_final_message(state, %{response | content: final_content})

      finish(state, :completed, :completed, %{"response" => content_text})
    end
  end

  # -------------------------------------------------------------------
  # Tool Execution
  # -------------------------------------------------------------------

  defp execute_tool_calls(state, tool_calls, response) do
    # Check for __relay__ or __done__ call first (swarm signal) — short-circuit if found
    case find_done_call(tool_calls) do
      {:ok, summary} ->
        handle_done_signal(state, response, summary)

      {:relay, next_agent_callname} ->
        handle_relay_signal(state, response, next_agent_callname)

      :none ->
        # Check for __complete__ call (pipeline signal) — short-circuit if found
        execute_tool_calls_after_done_check(state, tool_calls, response)
    end
  end

  defp execute_tool_calls_after_done_check(state, tool_calls, response) do
    # Check for __complete__ call first — short-circuit if found
    case find_complete_call(tool_calls) do
      {:ok, result} ->
        handle_complete_signal(state, response, result)

      :empty ->
        # Agent tried to complete with empty result — inject feedback and continue
        state =
          add_tool_results_to_context(state, tool_calls, [
            {:error,
             "Cannot complete with an empty result. Provide a meaningful summary of what was accomplished."}
          ])

        loop(state)

      :none ->
        execute_validated_tool_calls(state, tool_calls, response)
    end
  end

  defp execute_validated_tool_calls(state, tool_calls, response) do
    {valid_calls, invalid_calls} = validate_tool_calls_params(tool_calls, state.tools)

    if invalid_calls != [] do
      names = Enum.map(invalid_calls, fn {tc, _} -> tc.function.name end)

      Logger.warning(
        "Filtered #{length(invalid_calls)} tool call(s) with missing required params: #{inspect(names)}"
      )
    end

    invalid_results = build_invalid_call_results(invalid_calls)

    case valid_calls do
      [] ->
        state = add_tool_results_to_context(state, tool_calls, invalid_results)
        loop(state)

      calls ->
        check_doom_loop_and_execute(state, calls, invalid_calls, invalid_results, response)
    end
  end

  defp build_invalid_call_results(invalid_calls) do
    Enum.map(invalid_calls, fn {tc, missing} ->
      {:error, "#{tc.function.name}: missing required parameter(s): #{Enum.join(missing, ", ")}"}
    end)
  end

  defp check_doom_loop_and_execute(state, valid_calls, invalid_calls, invalid_results, response) do
    call_fingerprint = tool_calls_fingerprint(valid_calls)

    if doom_loop?(state.recent_tool_calls, call_fingerprint) do
      Logger.warning(
        "Doom loop detected: #{@doom_loop_threshold} identical consecutive tool calls"
      )

      finish(state, :failed, :doom_loop, %{"error" => "doom_loop"})
    else
      state = %{
        state
        | recent_tool_calls: track_tool_call(state.recent_tool_calls, call_fingerprint)
      }

      do_execute_tool_calls(state, valid_calls, invalid_calls, invalid_results, response)
    end
  end

  defp do_execute_tool_calls(state, valid_calls, invalid_calls, invalid_results, response) do
    case ApprovalGate.check_calls(state, valid_calls) do
      :proceed ->
        do_execute_approved_tool_calls(
          state,
          valid_calls,
          invalid_calls,
          invalid_results,
          response
        )

      {:paused, approval} ->
        Logger.info("Invocation paused for approval: #{approval.action_summary}")
        finish(state, :failed, :approval_rejected, %{"approval_id" => approval.id})
    end
  end

  defp do_execute_approved_tool_calls(
         state,
         valid_calls,
         invalid_calls,
         invalid_results,
         response
       ) do
    {state, valid_results} = execute_tool_batch(state, valid_calls)

    # Record step with first tool call info
    first_call = hd(valid_calls)

    {:ok, _step} =
      Orchestration.add_step(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        step_number: state.step_number,
        reasoning: Response.text(response),
        tool_name: first_call.function.name,
        tool_input: parse_json(first_call.function.arguments),
        tool_output: summarize_tool_results(valid_results),
        status: if(Enum.all?(valid_results, &match?({:ok, _}, &1)), do: :ok, else: :error)
      })

    # Build a result lookup from both valid and invalid calls
    valid_result_map = Map.new(Enum.zip(valid_calls, valid_results), fn {tc, r} -> {tc.id, r} end)

    invalid_result_map =
      Map.new(
        Enum.zip(
          Enum.map(invalid_calls, fn {tc, _} -> tc end),
          invalid_results
        ),
        fn {tc, r} -> {tc.id, r} end
      )

    result_map = Map.merge(valid_result_map, invalid_result_map)

    # Reconstruct results in the original tool_calls order from the assistant message
    original_calls = get_last_assistant_tool_calls(state.context)
    ordered_results = Enum.map(original_calls, fn tc -> Map.fetch!(result_map, tc.id) end)

    state = add_tool_results_to_context(state, original_calls, ordered_results)

    loop(state)
  end

  defp get_last_assistant_tool_calls(context) do
    context
    |> Enum.reverse()
    |> Enum.find_value([], fn
      %{role: :assistant, tool_calls: tcs} when is_list(tcs) -> tcs
      _ -> false
    end)
  end

  defp find_done_call(tool_calls) do
    relay_calls = Enum.filter(tool_calls, &(&1.function.name == @relay_tool_name))

    case relay_calls do
      [] -> find_legacy_done_call(tool_calls)
      calls -> resolve_relay_calls(calls)
    end
  end

  defp find_legacy_done_call(tool_calls) do
    case Enum.find(tool_calls, &(&1.function.name == @done_tool_name)) do
      nil ->
        :none

      tool_call ->
        args = parse_json(tool_call.function.arguments)
        summary = args["summary"] || "Party discussion complete"
        {:ok, summary}
    end
  end

  defp resolve_relay_calls(calls) do
    parsed_calls =
      Enum.map(calls, fn tc ->
        args = parse_json(tc.function.arguments)
        {tc, args["next_agent"] || "__done__"}
      end)

    case Enum.find(parsed_calls, fn {_tc, target} -> target != "__done__" end) do
      {_tc, target} -> {:relay, target}
      nil -> {:ok, "Party discussion complete"}
    end
  end

  defp handle_done_signal(state, response, summary) do
    # Record the done step
    {:ok, _step} =
      Orchestration.add_step(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        step_number: state.step_number,
        reasoning: Response.text(response),
        tool_name: @done_tool_name,
        tool_input: %{"summary" => summary},
        status: :ok
      })

    # Write the agent's actual response as the final message (not just the summary).
    # If the agent produced text content alongside __done__, use that; otherwise fall
    # back to the summary so there is always a visible assistant message.
    display_content =
      if Response.text(response) do
        response.content
      else
        Intent.text(summary)
      end

    write_final_message(state, %Response{
      content: display_content,
      thinking: response.thinking,
      usage: response.usage
    })

    # Finish with the __done__ signal in output so SwarmRunner can detect it
    finish(state, :completed, :completed, %{
      "tool" => @done_tool_name,
      "summary" => summary
    })
  end

  defp handle_relay_signal(state, response, next_agent_callname) do
    # Record the relay step
    {:ok, _step} =
      Orchestration.add_step(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        step_number: state.step_number,
        reasoning: Response.text(response),
        tool_name: @relay_tool_name,
        tool_input: %{"next_agent" => next_agent_callname},
        status: :ok
      })

    # Write the agent's response as the final message
    display_content =
      if Response.text(response) do
        response.content
      else
        Intent.text("Relaying to @#{next_agent_callname}")
      end

    write_final_message(state, %Response{
      content: display_content,
      thinking: response.thinking,
      usage: response.usage
    })

    # Finish with the relay signal so SwarmRunner can route directly
    finish(state, :completed, :completed, %{
      "tool" => @relay_tool_name,
      "next_agent" => next_agent_callname
    })
  end

  defp find_complete_call(tool_calls) do
    case Enum.find(tool_calls, &(&1.function.name == @complete_tool_name)) do
      nil ->
        :none

      tool_call ->
        args = parse_json(tool_call.function.arguments)
        result = args["result"] || ""

        if String.trim(result) == "" do
          :empty
        else
          {:ok, result}
        end
    end
  end

  defp handle_complete_signal(state, response, result) do
    # Record the completion step
    {:ok, _step} =
      Orchestration.add_step(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        step_number: state.step_number,
        reasoning: Response.text(response),
        tool_name: @complete_tool_name,
        tool_input: %{"result" => result},
        status: :ok
      })

    # Write final message if in a conversation
    write_final_message(state, %Response{content: result, usage: response.usage})

    finish(state, :completed, :completed, %{"result" => result})
  end

  defp execute_single_tool(state, tool_call) do
    tool_name = tool_call.function.name

    # Emit tool_started event
    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        agent_id: state.agent.id,
        event_type: :tool_started,
        summary: "Calling #{tool_name}",
        payload: %{"tool_call_id" => tool_call.id, "tool_name" => tool_name}
      })

    EventLog.append(:tool_started, %{
      agent_id: state.agent.id,
      invocation_id: state.invocation.id,
      tool_name: tool_name
    })

    result = call_tool_with_timeout(state, tool_call)

    case result do
      {:ok, output} ->
        {:ok, _} =
          Orchestration.add_event(%{
            invocation_id: state.invocation.id,
            workspace_id: state.invocation.workspace_id,
            agent_id: state.agent.id,
            event_type: :tool_finished,
            summary: "#{tool_name} completed",
            payload: %{"tool_call_id" => tool_call.id}
          })

        state = clear_failure_count(state, tool_name)
        {state, {:ok, output}}

      {:error, error} ->
        {:ok, _} =
          Orchestration.add_event(%{
            invocation_id: state.invocation.id,
            workspace_id: state.invocation.workspace_id,
            agent_id: state.agent.id,
            event_type: :tool_failed,
            summary: "#{tool_name} failed: #{stringify_error(error)}",
            payload: %{"tool_call_id" => tool_call.id, "error" => stringify_error(error)}
          })

        failure_count = get_failure_count(state, tool_name) + 1
        state = increment_failure_count(state, tool_name)
        handle_tool_failure(state, tool_call, tool_name, error, failure_count)
    end
  end

  defp handle_tool_failure(state, tool_call, tool_name, _error, failure_count)
       when failure_count < 2 do
    Logger.warning("Tool #{tool_name} failed (attempt #{failure_count}), retrying")

    case call_tool_with_timeout(state, tool_call) do
      {:ok, output} ->
        state = clear_failure_count(state, tool_name)
        {state, {:ok, output}}

      {:error, retry_error} ->
        {state, {:error, "#{tool_name} failed after retry: #{stringify_error(retry_error)}"}}
    end
  end

  defp handle_tool_failure(state, _tool_call, tool_name, error, failure_count) do
    {state,
     {:error, "#{tool_name} failed #{failure_count} consecutive times: #{stringify_error(error)}"}}
  end

  # -------------------------------------------------------------------
  # Parallel Tool Execution
  # -------------------------------------------------------------------

  @terminal_tools MapSet.new([@done_tool_name, @relay_tool_name, @complete_tool_name])

  defp execute_tool_batch(state, [single_call]) do
    {state, result} = execute_single_tool(state, single_call)
    {state, [result]}
  end

  defp execute_tool_batch(state, valid_calls) when state.max_tool_concurrency <= 1 do
    Enum.reduce(valid_calls, {state, []}, fn tool_call, {acc_state, acc_results} ->
      {new_state, result} = execute_single_tool(acc_state, tool_call)
      {new_state, acc_results ++ [result]}
    end)
  end

  defp execute_tool_batch(state, valid_calls) do
    {terminal, parallel} = split_terminal_tools(valid_calls)

    # Execute parallelizable tools via Harness
    parallel_results = execute_parallel_tools(state, parallel)

    # Execute terminal tools sequentially after
    {state, terminal_results} =
      Enum.reduce(terminal, {state, []}, fn tool_call, {acc_state, acc_results} ->
        {new_state, result} = execute_single_tool(acc_state, tool_call)
        {new_state, acc_results ++ [result]}
      end)

    # Reconcile failure counts from parallel results
    state = reconcile_parallel_failures(state, parallel_results)

    # Merge results in original order
    result_map = build_result_map(parallel_results, terminal, terminal_results)
    ordered = Enum.map(valid_calls, fn tc -> Map.fetch!(result_map, tc.id) end)

    {state, ordered}
  end

  defp split_terminal_tools(tool_calls) do
    Enum.split_with(tool_calls, fn tc ->
      not MapSet.member?(@terminal_tools, tc.function.name)
    end)
  end

  defp execute_parallel_tools(_state, []), do: []

  defp execute_parallel_tools(state, parallel_calls) do
    units =
      Enum.map(parallel_calls, fn tool_call ->
        group = tool_group_key(tool_call)
        {group, {tool_call.id, fn -> execute_tool_stateless(state, tool_call) end}}
      end)

    case Harness.run_grouped(units,
           max_concurrency: state.max_tool_concurrency,
           timeout: state.agent.local_agent.step_timeout_s * 1_000,
           surface: :react_tools
         ) do
      {:ok, results} -> results
      {:partial, successes, _failures} -> successes
    end
  end

  defp execute_tool_stateless(state, tool_call) do
    tool_name = tool_call.function.name

    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: state.invocation.id,
        workspace_id: state.invocation.workspace_id,
        agent_id: state.agent.id,
        event_type: :tool_started,
        summary: "Calling #{tool_name}",
        payload: %{"tool_call_id" => tool_call.id, "tool_name" => tool_name}
      })

    EventLog.append(:tool_started, %{
      agent_id: state.agent.id,
      invocation_id: state.invocation.id,
      tool_name: tool_name
    })

    result = call_tool_with_timeout(state, tool_call)

    case result do
      {:ok, output} ->
        {:ok, _} =
          Orchestration.add_event(%{
            invocation_id: state.invocation.id,
            workspace_id: state.invocation.workspace_id,
            agent_id: state.agent.id,
            event_type: :tool_finished,
            summary: "#{tool_name} completed",
            payload: %{"tool_call_id" => tool_call.id}
          })

        {:ok, tool_name, {:ok, output}}

      {:error, error} ->
        {:ok, _} =
          Orchestration.add_event(%{
            invocation_id: state.invocation.id,
            workspace_id: state.invocation.workspace_id,
            agent_id: state.agent.id,
            event_type: :tool_failed,
            summary: "#{tool_name} failed: #{stringify_error(error)}",
            payload: %{"tool_call_id" => tool_call.id, "error" => stringify_error(error)}
          })

        {:error, tool_name, error}
    end
  end

  defp tool_group_key(tool_call) do
    name = tool_call.function.name

    cond do
      MapSet.member?(@terminal_tools, name) -> {:terminal, name}
      name in ~w(__generate_image__ __generate_video__) -> {:media, name}
      name in ~w(__create_artifact__ __update_artifact__ __read_artifact__) -> {:artifact, name}
      BuiltinTools.builtin?(name) -> {:builtin, name}
      true -> {:mcp, mcp_server_prefix(name)}
    end
  end

  defp mcp_server_prefix(name) do
    case String.split(name, "_", parts: 2) do
      [server, _tool] -> server
      _ -> name
    end
  end

  defp reconcile_parallel_failures(state, results) do
    Enum.reduce(results, state, fn
      {:ok, _id, {:ok, tool_name, _output}}, acc -> clear_failure_count(acc, tool_name)
      {:ok, _id, {:error, tool_name, _error}}, acc -> increment_failure_count(acc, tool_name)
      _, acc -> acc
    end)
  end

  defp build_result_map(parallel_results, terminal_calls, terminal_results) do
    parallel_map =
      Map.new(parallel_results, fn {:ok, tc_id, result} ->
        case result do
          {:ok, _tool_name, output} -> {tc_id, {:ok, output}}
          {:error, _tool_name, error} -> {tc_id, {:error, stringify_error(error)}}
        end
      end)

    terminal_map =
      Map.new(Enum.zip(terminal_calls, terminal_results), fn {tc, result} ->
        {tc.id, result}
      end)

    Map.merge(parallel_map, terminal_map)
  end

  # -------------------------------------------------------------------
  # Tool Call Param Validation
  # -------------------------------------------------------------------

  defp validate_tool_calls_params(tool_calls, tools) do
    schema_index = build_schema_index(tools)

    Enum.split_with(tool_calls, fn tc ->
      case Map.get(schema_index, tc.function.name) do
        nil ->
          # Unknown tool — let execution handle it
          true

        required_fields ->
          args = parse_json(tc.function.arguments)
          Enum.all?(required_fields, &Map.has_key?(args, &1))
      end
    end)
    |> case do
      {valid, invalid_tcs} ->
        invalid_with_reasons =
          Enum.map(invalid_tcs, fn tc ->
            required = Map.get(schema_index, tc.function.name, [])
            args = parse_json(tc.function.arguments)
            missing = Enum.reject(required, &Map.has_key?(args, &1))
            {tc, missing}
          end)

        {valid, invalid_with_reasons}
    end
  end

  defp build_schema_index(nil), do: %{}

  defp build_schema_index(tools) do
    Map.new(tools, fn tool ->
      f = tool[:function] || tool["function"] || %{}
      name = f[:name] || f["name"]
      params = f[:parameters] || f["parameters"] || %{}
      required = params["required"] || params[:required] || []
      {name, required}
    end)
  end

  # -------------------------------------------------------------------
  # Doom Loop Detection
  # -------------------------------------------------------------------

  defp tool_calls_fingerprint(tool_calls) do
    tool_calls
    |> Enum.map(fn tc ->
      name = tc.function.name
      args = tc.function.arguments || ""
      :erlang.phash2({name, args})
    end)
    |> :erlang.phash2()
  end

  defp doom_loop?(recent, fingerprint) do
    length(recent) >= @doom_loop_threshold and
      Enum.all?(recent, &(&1 == fingerprint))
  end

  defp track_tool_call(recent, fingerprint) do
    [fingerprint | recent] |> Enum.take(@doom_loop_threshold)
  end

  defp call_tool_with_timeout(state, tool_call) do
    timeout = state.agent.local_agent.step_timeout_s * 1_000

    if state.tool_executor do
      context = %{agent_id: state.agent.id, workspace_id: state.agent.workspace_id}
      task = Task.async(fn -> state.tool_executor.execute(tool_call, context) end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          result

        nil ->
          {:error, "tool execution timed out after #{state.agent.local_agent.step_timeout_s}s"}
      end
    else
      {:error, "no tool executor configured"}
    end
  end

  # -------------------------------------------------------------------
  # Orchestration Tool & Context Injection
  # -------------------------------------------------------------------

  defp inject_orchestration_tools(
         tools,
         pipeline_stage?,
         swarm?,
         swarm_mode,
         swarm_members,
         agent
       ) do
    tools
    |> maybe_add_complete_tool(pipeline_stage?)
    |> maybe_add_relay_tool(swarm?, swarm_mode, swarm_members, agent)
  end

  defp maybe_add_complete_tool(tools, true), do: (tools || []) ++ [@complete_tool_def]
  defp maybe_add_complete_tool(tools, _), do: tools

  # round_robin and directed agents don't get __relay__:
  # - round_robin: the turn router cycles them
  # - directed: the coordinator decides when to stop
  defp maybe_add_relay_tool(tools, true, :relay, members, agent) do
    other_callnames =
      members
      |> Enum.reject(&(&1.id == agent.id))
      |> Enum.filter(&(is_binary(&1.callname) and &1.callname != ""))
      |> Enum.map(& &1.callname)

    if other_callnames == [] do
      tools
    else
      relay_tool = %{
        type: "function",
        function: %{
          name: @relay_tool_name,
          description:
            "Hand off to another party member to contribute their perspective, or signal \"__done__\" when the task is complete. " <>
              "You MUST call this exactly once at the end of your response. You are part of a team — prefer relaying to let others contribute before finishing.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "next_agent" => %{
                "type" => "string",
                "description" =>
                  "The callname of the next member to respond, or \"__done__\" when the task needs no further input.",
                "enum" => other_callnames ++ ["__done__"]
              }
            },
            "required" => ["next_agent"]
          }
        }
      }

      (tools || []) ++ [relay_tool]
    end
  end

  defp maybe_add_relay_tool(tools, _, _, _, _), do: tools

  defp inject_swarm_context_if_needed(context, agent, true, members, mode)
       when members != [] do
    inject_swarm_context(context, agent, members, mode)
  end

  defp inject_swarm_context_if_needed(context, _, _, _, _), do: context

  # -------------------------------------------------------------------
  # Swarm Context Injection
  # -------------------------------------------------------------------

  defp inject_swarm_context(context, current_agent, members, mode) do
    other_members =
      members
      |> Enum.reject(&(&1.id == current_agent.id))
      |> Enum.map(&format_member_line/1)

    if other_members == [] do
      context
    else
      member_list = Enum.join(other_members, "\n")

      instructions =
        case mode do
          :relay ->
            """
            ## Party Collaboration (Chain Spell Mode)
            You are @#{current_agent.callname} in a team of agents working together. Other members:
            #{member_list}

            IMPORTANT: You MUST call the __relay__ tool exactly once at the end of your response.

            ## How to collaborate
            You are part of a team. After contributing your part, relay to the member whose
            expertise best complements yours so they can add their perspective. Each member
            brings unique value — let others contribute before finishing the chain.

            ## When to relay to another member
            - Another member has relevant expertise that would enrich the response.
            - The task benefits from multiple perspectives or specializations.
            - Not all members have had a chance to contribute yet.

            ## When to use "__done__"
            - The task has been thoroughly addressed and no member can add meaningful value.
            - The conversation is going in circles — members are repeating earlier points.
            - You have nothing substantive to add beyond what has already been said.

            You must pick from the exact callnames listed above.\
            """

          :round_robin ->
            """
            ## Party Collaboration (Circle Mode)
            You are @#{current_agent.callname}. Other members:
            #{member_list}

            The party cycles through all members automatically. Just respond to the conversation
            with your contribution. Do NOT try to complete the entire task alone — other members
            will take their turns after you. Focus on YOUR area of expertise and build on what
            others have said.\
            """

          _ ->
            """
            ## Party Collaboration (Summoning Mode)
            You are @#{current_agent.callname}. Other members:
            #{member_list}

            A coordinator decides who speaks next. Just respond with your best contribution
            to the conversation. Focus on YOUR area of expertise and build on what others
            have said. Do NOT try to address the entire request alone.\
            """
        end

      swarm_msg = %{role: :system, content: Intent.text(instructions)}

      # Insert after the first system message (harness/personality)
      case context do
        [%{role: :system} = first | rest] -> [first, swarm_msg | rest]
        _ -> [swarm_msg | context]
      end
    end
  end

  defp format_member_line(agent) do
    desc =
      case Agent.description(agent) do
        nil -> ""
        d -> " — #{d}"
      end

    "  - @#{agent.callname}#{desc}"
  end

  # Appends a trailing reminder for relay-mode swarms so the LLM sees
  # the @callname instruction at the very end of the context (recency bias).
  # This is ephemeral — not persisted in state.context — only used for the
  # current inference call.
  defp maybe_append_mention_reminder(state), do: state.context

  # -------------------------------------------------------------------
  # Context Management
  # -------------------------------------------------------------------

  defp add_tool_results_to_context(state, tool_calls, tool_results) do
    max_chars = state.max_tool_output_chars

    tool_messages =
      Enum.zip(tool_calls, tool_results)
      |> Enum.map(fn {tool_call, result} ->
        content =
          case result do
            {:ok, output} -> output
            {:error, error} -> "Error: #{stringify_error(error)}"
          end

        content = truncate_tool_output(content, max_chars)

        %{role: :tool, content: Intent.text(content), tool_call_id: tool_call.id}
      end)

    %{state | context: state.context ++ tool_messages}
  end

  defp truncate_tool_output(content, max_chars) when is_binary(content) do
    if String.length(content) > max_chars do
      truncated = String.slice(content, 0, max_chars)

      truncated <>
        "\n\n[OUTPUT TRUNCATED — showing #{max_chars} of #{String.length(content)} characters. " <>
        "Request specific files or smaller ranges instead of broad listings.]"
    else
      content
    end
  end

  defp truncate_tool_output(content, _max_chars), do: content

  @doc false
  # Enforces the context budget by evicting oldest tool/assistant exchanges
  # when the estimated token count exceeds the budget.
  # Preserves: system prompt (first msg), last user message, and the most
  # recent assistant+tool exchange.
  defp enforce_context_budget(state) do
    budget = state.context_budget
    estimated = Ledger.estimate_context_tokens(state.context)

    if estimated <= budget do
      state
    else
      Logger.warning(
        "Context #{estimated} tokens exceeds budget #{budget}, evicting old messages"
      )

      %{state | context: evict_until_under_budget(state.context, budget)}
    end
  end

  defp evict_until_under_budget(context, budget) do
    # Partition into protected and evictable messages
    {system_msgs, rest} = Enum.split_while(context, &(&1.role == :system))

    # Find last user message index — everything after it is the current exchange
    last_user_idx =
      rest
      |> Enum.with_index()
      |> Enum.filter(fn {msg, _i} -> msg.role == :user end)
      |> List.last()
      |> case do
        {_msg, idx} -> idx
        nil -> length(rest)
      end

    {history, current_exchange} = Enum.split(rest, last_user_idx)

    # Evict from history (oldest first) — drop tool results first, then assistants
    do_evict(system_msgs, history, current_exchange, budget)
  end

  defp do_evict(system_msgs, history, current_exchange, budget) do
    protected = system_msgs ++ current_exchange
    protected_cost = Ledger.estimate_context_tokens(protected)

    if protected_cost >= budget do
      # Even protected messages exceed budget — keep only them, nothing we can do
      protected
    else
      remaining_budget = budget - protected_cost
      kept_history = keep_newest_under_budget(Enum.reverse(history), remaining_budget)
      system_msgs ++ kept_history ++ current_exchange
    end
  end

  defp keep_newest_under_budget(reversed_history, budget) do
    {kept, _remaining} =
      Enum.reduce(reversed_history, {[], budget}, fn msg, {acc, remaining} ->
        cost = Ledger.estimate_message_tokens(msg)

        if cost <= remaining do
          {[msg | acc], remaining - cost}
        else
          {acc, remaining}
        end
      end)

    kept
  end

  defp max_completion_tokens(state) do
    context_length = state.agent.local_agent.context_length || @default_context_length
    estimated_prompt = Ledger.estimate_context_tokens(state.context)
    available = context_length - estimated_prompt

    # Clamp between 256 and 16384
    available |> max(256) |> min(16_384)
  end

  # -------------------------------------------------------------------
  # Completion
  # -------------------------------------------------------------------

  defp write_final_message(state, response) do
    content = response.content

    if state.invocation.conversation_id && content && content != [] do
      visibility =
        if state.invocation.depth > 0, do: :internal, else: :public

      token_count =
        if response.usage do
          response.usage.total_tokens
        else
          Ledger.estimate_tokens(content)
        end

      {:ok, _} =
        Conversations.add_message(%{
          conversation_id: state.invocation.conversation_id,
          invocation_id: state.invocation.id,
          agent_id: state.agent.id,
          role: :assistant,
          content: content,
          thinking: response.thinking,
          visibility: visibility,
          token_count: token_count,
          provider_name: state.provider.name,
          model_name: state.agent.local_agent.model
        })
    end
  end

  defp finish(state, status, end_reason, output \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, invocation} =
      Orchestration.update_invocation_status(state.invocation, status, %{
        end_reason: end_reason,
        output: output,
        completed_at: now
      })

    # Emit completion event
    event_type = if status == :completed, do: :completed, else: :failed

    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: invocation.id,
        workspace_id: invocation.workspace_id,
        agent_id: state.agent.id,
        event_type: event_type,
        summary: "Invocation #{status} (#{end_reason})",
        payload: %{"end_reason" => to_string(end_reason), "steps" => state.step_number}
      })

    # In-memory event log for real-time observability
    EventLog.append(:"invocation_#{event_type}", %{
      agent_id: state.agent.id,
      invocation_id: invocation.id,
      workspace_id: invocation.workspace_id,
      end_reason: end_reason,
      steps: state.step_number,
      tokens: state.token_count
    })

    # Record token usage for analytics
    record_token_usage(state, invocation)

    # Enqueue async compaction if the conversation has grown large
    maybe_enqueue_compaction(invocation, state.agent)

    case status do
      :completed -> {:ok, invocation}
      :failed -> {:error, end_reason, invocation}
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp maybe_enqueue_compaction(invocation, agent) do
    if invocation.conversation_id do
      Workers.enqueue_compaction(%{
        conversation_id: invocation.conversation_id,
        agent_id: agent.id
      })
    end

    :ok
  end

  defp record_token_usage(state, invocation) do
    if state.token_count > 0 do
      cost_usd =
        Ledger.estimate_cost(
          state.agent.local_agent.model,
          state.prompt_tokens,
          state.completion_tokens
        )

      Ledger.record_usage(%{
        workspace_id: invocation.workspace_id,
        agent_id: state.agent.id,
        provider_id: state.provider.id,
        invocation_id: invocation.id,
        model: state.agent.local_agent.model,
        prompt_tokens: state.prompt_tokens,
        completion_tokens: state.completion_tokens,
        total_tokens: state.token_count,
        estimated: !state.has_real_usage,
        cost_usd: cost_usd
      })
    end
  end

  defp total_timeout_exceeded?(state) do
    elapsed = System.monotonic_time(:millisecond) - state.started_at
    elapsed >= state.agent.local_agent.total_timeout_s * 1_000
  end

  defp add_timeout_message(state) do
    if state.invocation.conversation_id do
      Conversations.add_message(%{
        conversation_id: state.invocation.conversation_id,
        agent_id: state.agent.id,
        role: :system,
        content:
          "#{state.agent.name} timed out after #{state.agent.local_agent.total_timeout_s}s. " <>
            "You can adjust the timeout in summon or realm settings.",
        visibility: :public,
        provider_name: state.provider.name,
        model_name: state.agent.local_agent.model
      })
    end
  end

  defp check_token_cap(state) do
    Ledger.check_invocation_cap(
      state.invocation.id,
      state.agent.local_agent.max_tokens_per_invocation
    )
  end

  defp track_tokens(state, %Response{usage: nil} = response) do
    estimated = Ledger.estimate_tokens(response.content)
    %{state | token_count: state.token_count + estimated}
  end

  defp track_tokens(state, %Response{usage: usage}) do
    %{
      state
      | token_count: state.token_count + usage.total_tokens,
        prompt_tokens: state.prompt_tokens + (usage.prompt_tokens || 0),
        completion_tokens: state.completion_tokens + (usage.completion_tokens || 0),
        has_real_usage: true
    }
  end

  defp get_failure_count(state, tool_name) do
    Map.get(state.consecutive_failures, tool_name, 0)
  end

  defp increment_failure_count(state, tool_name) do
    count = get_failure_count(state, tool_name) + 1
    %{state | consecutive_failures: Map.put(state.consecutive_failures, tool_name, count)}
  end

  defp clear_failure_count(state, tool_name) do
    %{state | consecutive_failures: Map.delete(state.consecutive_failures, tool_name)}
  end

  defp parse_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, parsed} -> parsed
      _ -> %{"raw" => str}
    end
  end

  defp parse_json(_), do: %{}

  defp summarize_tool_results(results) do
    %{
      "results" =>
        Enum.map(results, fn
          {:ok, output} -> %{"status" => "ok", "output" => output}
          {:error, error} -> %{"status" => "error", "error" => stringify_error(error)}
        end)
    }
  end

  defp stringify_error(error) when is_binary(error), do: error
  defp stringify_error(error), do: inspect(error)

  defp format_api_error(status, %{"error" => %{"message" => msg}}) when is_binary(msg) do
    "Provider returned HTTP #{status}: #{msg}"
  end

  defp format_api_error(status, %{"error" => msg}) when is_binary(msg) do
    "Provider returned HTTP #{status}: #{msg}"
  end

  defp format_api_error(status, body) when is_binary(body) and body != "" do
    "Provider returned HTTP #{status}: #{String.slice(body, 0, 200)}"
  end

  defp format_api_error(status, body) when is_map(body) do
    "Provider returned HTTP #{status}: #{inspect(body) |> String.slice(0, 200)}"
  end

  defp format_api_error(status, _body) do
    "Provider returned HTTP #{status}"
  end

  defp format_error(%{reason: reason}), do: format_error(reason)
  defp format_error(:econnrefused), do: "Connection refused — is the provider online?"
  defp format_error(:timeout), do: "Request timed out"
  defp format_error(:closed), do: "Connection closed by provider"
  defp format_error(reason) when is_atom(reason), do: "Network error: #{reason}"
  defp format_error(reason), do: inspect(reason)

  defp maybe_add_thinking(map, nil), do: map
  defp maybe_add_thinking(map, ""), do: map
  defp maybe_add_thinking(map, thinking), do: Map.put(map, :thinking, thinking)

  # Extracts the last non-empty tool result from context as a fallback
  # when a model produces no text content in its final response.
  defp last_tool_output(context) do
    context
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: :tool, content: content} when is_binary(content) and content != "" -> content
      _ -> nil
    end)
  end
end
