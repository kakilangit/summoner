defmodule Summoner.Domain.Policies.TurnRouter do
  @moduledoc """
  Stateless turn router for Party execution.

  Determines which agent should respond next based on the swarm's mode,
  the conversation history, and the swarm membership.

  ## Modes

  - `:round_robin` — members take turns in order, cycling continuously
    until the SwarmRunner's max_turns guard terminates the loop
  - `:relay` — agents hand off via the __relay__ tool (structured routing);
    TurnRouter only picks the first responder, subsequent routing is in SwarmRunner
  - `:directed` — coordinator LLM decides who speaks next (handled by caller)
  """

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Swarm

  @doc """
  Determines the next agent to respond.

  Returns `{:ok, agent}` or `:done`.

  For `:directed` mode, this is not called directly — the coordinator
  routing is handled by `SwarmRunner` which calls the coordinator LLM.
  """
  @spec next_agent(Swarm.t(), [map()], [Agent.t()]) :: {:ok, Agent.t()} | :done
  def next_agent(%Swarm{mode: :round_robin}, messages, members) do
    round_robin(messages, members)
  end

  def next_agent(%Swarm{mode: :relay}, messages, members) do
    relay(messages, members)
  end

  def next_agent(%Swarm{mode: :directed}, _messages, _members) do
    # Directed routing is handled by SwarmRunner via coordinator LLM
    :done
  end

  # -------------------------------------------------------------------
  # Round-robin
  # -------------------------------------------------------------------

  defp round_robin([], [first | _]), do: {:ok, first}
  defp round_robin(_messages, []), do: :done

  defp round_robin(messages, members) do
    last_msg = List.last(messages)

    if last_msg.role == :user do
      {:ok, hd(members)}
    else
      last_agent_id = last_msg[:agent_id]

      case find_next_member(last_agent_id, members) do
        nil -> :done
        agent -> {:ok, agent}
      end
    end
  end

  defp find_next_member(nil, [first | _]), do: first

  defp find_next_member(agent_id, members) do
    case Enum.find_index(members, &(&1.id == agent_id)) do
      nil ->
        hd(members)

      idx ->
        next_idx = rem(idx + 1, length(members))
        Enum.at(members, next_idx)
    end
  end

  # -------------------------------------------------------------------
  # Relay (structured tool-based handoff)
  # -------------------------------------------------------------------

  # For relay mode, routing after the first turn is handled by the __relay__
  # tool output in SwarmRunner. TurnRouter only picks the first responder.
  defp relay([], [first | _]), do: {:ok, first}
  defp relay(_messages, []), do: :done

  defp relay(messages, members) do
    last_msg = List.last(messages)

    if last_msg.role == :user do
      {:ok, hd(members)}
    else
      # After the first agent responds, SwarmRunner handles relay routing
      # via structured tool output. This path shouldn't be reached in normal
      # operation but returns :done as a safe fallback.
      :done
    end
  end
end
