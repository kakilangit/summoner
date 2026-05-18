defmodule Summoner.Swarms.SwarmRunner do
  @moduledoc """
  Manages the turn loop for a swarm (swarm) conversation.

  When a user sends a message to a swarm session, the SwarmRunner
  determines which agents respond and in what order, executing each
  agent's turn via the standard AgentServer invocation path.

  The runner is designed to run in a spawned Task (fire-and-forget)
  so it doesn't block the LiveView process.

  ## Flow

  1. User sends message
  2. SwarmRunner determines next agent via TurnRouter (or coordinator LLM)
  3. Agent's invocation runs (synchronous call to AgentServer)
  4. Agent response is written to conversation
  5. Turn count increments; check termination conditions
  6. If more turns needed, goto step 2
  7. Broadcast `:swarm_done` when cycle ends
  """

  require Logger

  alias Summoner.Agents.Server, as: AgentServer
  alias Summoner.Broadcasts
  alias Summoner.Conversations
  alias Summoner.Orchestration
  alias Summoner.Swarms.{SwarmCoordinator, TurnRouter}

  @done_tool_name "__done__"
  @relay_tool_name "__relay__"

  @doc """
  Starts a swarm turn cycle asynchronously.

  Spawns a Task under the application's TaskSupervisor. The caller
  (usually ConversationLive.Show) receives PubSub broadcasts for turn updates.
  """
  def run_async(swarm, conversation, user_message, scope) do
    Task.Supervisor.start_child(Summoner.TaskSupervisor, fn ->
      run(swarm, conversation, user_message, scope)
    end)
  end

  @doc """
  Runs the swarm turn cycle synchronously.

  Returns `:ok` when the cycle completes.
  """
  def run(swarm, conversation, user_message, scope) do
    workspace_id = swarm.workspace_id

    # Load members ordered by insertion time
    members = load_members(swarm)

    if members == [] do
      Logger.warning("Swarm #{swarm.id} has no members, skipping turn cycle")
      broadcast_done(workspace_id, swarm.id, conversation.id, "No members in swarm")
      :ok
    else
      state = %{
        swarm: swarm,
        conversation: conversation,
        scope: scope,
        workspace_id: workspace_id,
        members: members,
        turn_count: 0,
        consecutive_failures: 0,
        max_turns: effective_turn_limit(swarm, members, user_message),
        last_message: user_message
      }

      turn_loop(state)
    end
  end

  # -------------------------------------------------------------------
  # Turn Limit Resolution
  # -------------------------------------------------------------------

  # For round_robin: default is one full cycle (len(members)),
  # user can override with explicit turn count, hard-capped by max_turns.
  # Other modes always use max_turns directly.
  defp effective_turn_limit(%{mode: :round_robin} = swarm, members, user_message) do
    hard_limit = swarm.max_turns

    case parse_turn_override(user_message) do
      {:ok, requested} -> min(requested, hard_limit)
      :none -> min(length(members), hard_limit)
    end
  end

  defp effective_turn_limit(swarm, _members, _user_message), do: swarm.max_turns

  @turn_override_pattern ~r/(\d+)\s*(?:turns?|rounds?|cycles?|times?)/i

  defp parse_turn_override(nil), do: :none

  defp parse_turn_override(message) when is_binary(message) do
    case Regex.run(@turn_override_pattern, message) do
      [_, count_str] ->
        case Integer.parse(count_str) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> :none
        end

      _ ->
        :none
    end
  end

  defp parse_turn_override(%{content: content}) when is_binary(content) do
    parse_turn_override(content)
  end

  defp parse_turn_override(_), do: :none

  # -------------------------------------------------------------------
  # Turn Loop
  # -------------------------------------------------------------------

  @max_consecutive_failures 3

  defp turn_loop(%{consecutive_failures: failures} = state)
       when failures >= @max_consecutive_failures do
    Logger.error("Swarm #{state.swarm.id} aborting after #{failures} consecutive agent failures")

    {:ok, _} =
      Conversations.add_message(%{
        conversation_id: state.conversation.id,
        role: :system,
        content:
          "Swarm stopped: #{failures} consecutive agent failures. Check provider configuration.",
        visibility: :public
      })

    broadcast_done(
      state.workspace_id,
      state.swarm.id,
      state.conversation.id,
      state.members
    )
  end

  defp turn_loop(%{turn_count: count, max_turns: max} = state) when count >= max do
    Logger.info("Swarm #{state.swarm.id} reached max turns (#{max})")

    {:ok, _} =
      Conversations.add_message(%{
        conversation_id: state.conversation.id,
        role: :system,
        content: "Turn limit reached (#{max} turns). Send a new message to continue.",
        visibility: :public
      })

    broadcast_done(
      state.workspace_id,
      state.swarm.id,
      state.conversation.id,
      "Turn limit reached"
    )

    :ok
  end

  defp turn_loop(state) do
    case determine_next_agent(state) do
      {:ok, agent} ->
        execute_turn(state, agent)

      {:done, summary} ->
        # Coordinator provided a summary — write it as system message
        {:ok, _} =
          Conversations.add_message(%{
            conversation_id: state.conversation.id,
            role: :system,
            content: summary,
            visibility: :public
          })

        broadcast_done(
          state.workspace_id,
          state.swarm.id,
          state.conversation.id,
          summary
        )

        :ok

      :done ->
        broadcast_done(
          state.workspace_id,
          state.swarm.id,
          state.conversation.id,
          "Turn cycle complete"
        )

        :ok
    end
  end

  defp determine_next_agent(state) do
    case state.swarm.mode do
      :directed ->
        # Use coordinator LLM to decide
        SwarmCoordinator.route(state.swarm, state.conversation, state.members)

      mode when mode in [:round_robin, :relay] ->
        # Load recent messages for routing decision
        messages =
          Conversations.list_messages(state.conversation.id,
            visibility: :public,
            limit: 20
          )

        context_messages =
          Enum.map(messages, fn msg ->
            %{
              role: msg.role,
              content: msg.content,
              agent_id: msg.agent_id
            }
          end)

        TurnRouter.next_agent(state.swarm, context_messages, state.members)
    end
  end

  defp execute_turn(state, agent) do
    # Broadcast which agent is responding
    topic = Broadcasts.swarm_topic(state.workspace_id, state.swarm.id)

    Broadcasts.broadcast(
      topic,
      {:swarm_turn, state.conversation.id, agent.id}
    )

    # Ensure agent server is started and invoke synchronously
    AgentServer.ensure_started(state.workspace_id, agent.id)

    # Use synchronous invoke so we can check the result for __done__
    result =
      invoke_with_timeout(
        state.workspace_id,
        agent,
        state.conversation.id,
        state.last_message,
        state.scope,
        state.members,
        state.swarm.mode
      )

    case result do
      {:ok, invocation} ->
        state = %{state | consecutive_failures: 0}
        handle_turn_result(state, agent, invocation)

      {:error, :timeout} ->
        Logger.warning("Agent #{agent.name} timed out in swarm #{state.swarm.id}")

        # Cancel the running invocation so it doesn't write orphaned messages
        cancel_agent_invocations(state.workspace_id, agent.id, state.conversation.id)

        # Write a visible system message so the user sees what happened
        {:ok, _} =
          Conversations.add_message(%{
            conversation_id: state.conversation.id,
            role: :system,
            content:
              "#{agent.name} timed out after #{agent.total_timeout_s}s. " <>
                "Skipping to next member. You can adjust the timeout in the familiar's settings.",
            visibility: :public
          })

        Broadcasts.broadcast(
          topic,
          {:swarm_timeout, state.conversation.id, agent.id}
        )

        # Skip this agent, continue with next turn
        state = %{
          state
          | turn_count: state.turn_count + 1,
            consecutive_failures: state.consecutive_failures + 1
        }

        turn_loop(state)

      {:error, reason} ->
        Logger.error("Agent #{agent.name} failed in swarm: #{inspect(reason)}")

        state = %{
          state
          | turn_count: state.turn_count + 1,
            consecutive_failures: state.consecutive_failures + 1
        }

        turn_loop(state)
    end
  end

  defp handle_turn_result(state, _agent, invocation) do
    output = invocation.output || %{}

    case output do
      %{"tool" => @relay_tool_name, "next_agent" => callname} ->
        # Structured relay — find the agent by callname
        case find_member_by_callname(state.members, callname) do
          {:ok, next_agent} ->
            state = %{state | turn_count: state.turn_count + 1, last_message: nil}
            execute_turn(state, next_agent)

          :not_found ->
            # Invalid callname — treat as done
            Logger.warning("Relay target '#{callname}' not found in swarm members")

            broadcast_done(
              state.workspace_id,
              state.swarm.id,
              state.conversation.id,
              "Relay target not found"
            )

            :ok
        end

      %{"tool" => @done_tool_name, "summary" => summary} ->
        # Legacy __done__ or relay __done__ signal
        if state.swarm.mode == :directed do
          state = %{
            state
            | turn_count: state.turn_count + 1,
              last_message: nil
          }

          turn_loop(state)
        else
          broadcast_done(
            state.workspace_id,
            state.swarm.id,
            state.conversation.id,
            summary
          )

          :ok
        end

      _ ->
        # Continue to next turn — don't pass a message since the agent's
        # response is already in the conversation history. The next agent
        # will read it via Memory.assemble_context/load_history.
        state = %{
          state
          | turn_count: state.turn_count + 1,
            last_message: nil
        }

        turn_loop(state)
    end
  end

  defp find_member_by_callname(members, callname) do
    lowered = String.downcase(callname)

    case Enum.find(members, fn agent ->
           is_binary(agent.callname) and String.downcase(agent.callname) == lowered
         end) do
      nil -> :not_found
      agent -> {:ok, agent}
    end
  end

  defp invoke_with_timeout(
         workspace_id,
         agent,
         conversation_id,
         message,
         scope,
         members,
         swarm_mode
       ) do
    timeout_s = agent.total_timeout_s

    task =
      Task.async(fn ->
        AgentServer.invoke(workspace_id, agent.id, %{
          conversation_id: conversation_id,
          message: message,
          scope: scope,
          react_opts: %{
            swarm: true,
            swarm_members: members,
            swarm_mode: swarm_mode
          }
        })
      end)

    case Task.yield(task, timeout_s * 1_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp load_members(swarm) do
    swarm = Summoner.Repo.preload(swarm, members: Summoner.Swarms.member_query())

    Enum.map(swarm.members, & &1.agent)
  end

  defp cancel_agent_invocations(workspace_id, agent_id, conversation_id) do
    # Find running invocations for this agent+conversation and cancel them
    running_ids = Orchestration.running_invocation_ids(agent_id, conversation_id)

    for id <- running_ids do
      AgentServer.cancel(workspace_id, agent_id, id)
    end
  end

  defp broadcast_done(workspace_id, swarm_id, conversation_id, summary) do
    # Cancel any remaining queued invocations for this conversation
    # to prevent stale invocations from running after the swarm is done
    Orchestration.cancel_queued_invocations_for_conversation(conversation_id)

    topic = Broadcasts.swarm_topic(workspace_id, swarm_id)
    Broadcasts.broadcast(topic, {:swarm_done, conversation_id, summary})
  end
end
