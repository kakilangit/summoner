defmodule Summoner.Domain.Policies.Failover do
  @moduledoc """
  Pure domain policy for agent failover decisions.

  Determines whether a failed invocation should trigger failover
  to a backup agent. No side effects — returns resolution intents.

  The failover chain is an ordered list of `AgentFailoverEntry` structs
  preloaded on the agent (sorted by position). This policy does NOT
  resolve agents from the database — it only decides *whether* to
  failover and *which strategy* to use. The service layer walks the
  chain and resolves active backup agents.
  """

  alias Summoner.Domain.Schemas.Agent

  @type failover_result ::
          {:failover, :auto}
          | :failover_pending
          | {:failover_delayed, non_neg_integer()}
          | :no_backup
          | :max_depth_reached
          | :not_eligible

  @failover_errors [
    :api_error,
    :timeout,
    :connection_error,
    :a2a_error,
    :model_not_found,
    :budget_exhausted
  ]

  @failover_http_statuses [429, 500, 502, 503, 529]

  @doc """
  Decides what to do when an agent's invocation fails.

  Returns a failover intent or a reason why failover can't happen.
  The agent must have `failover_chain` preloaded (list of AgentFailoverEntry).
  """
  @spec handle_failure(Agent.t(), term(), non_neg_integer()) :: failover_result()
  def handle_failure(%Agent{} = agent, error, current_depth) do
    cond do
      not failover_eligible?(error) ->
        :not_eligible

      Enum.empty?(agent.failover_chain || []) ->
        :no_backup

      current_depth >= agent.max_failover_depth ->
        :max_depth_reached

      true ->
        case agent.failover_strategy do
          :auto -> {:failover, :auto}
          :manual -> :failover_pending
          :notify_then_auto -> {:failover_delayed, agent.failover_delay_ms}
        end
    end
  end

  @doc """
  Checks whether an error type qualifies for failover.
  """
  @spec failover_eligible?(term()) :: boolean()
  def failover_eligible?({:api_error, status, _body}) when status in @failover_http_statuses,
    do: true

  def failover_eligible?({error_type, _details}) when error_type in @failover_errors, do: true
  def failover_eligible?(error_type) when error_type in @failover_errors, do: true
  def failover_eligible?(_), do: false

  @doc """
  Validates that adding `backup_agent_id` to `agent_id`'s failover chain
  would not create a cycle.

  `get_chain_fn` is a function `(agent_id) -> [%AgentFailoverEntry{}]` that
  returns the failover chain for a given agent. This keeps the policy pure —
  the caller (service layer) provides the lookup function.
  """
  @spec creates_cycle?(String.t(), String.t(), (String.t() -> [map()])) :: boolean()
  def creates_cycle?(agent_id, backup_agent_id, get_chain_fn) do
    agent_id == backup_agent_id or
      do_cycle_check(agent_id, backup_agent_id, get_chain_fn, MapSet.new())
  end

  # --- Private ---

  defp do_cycle_check(agent_id, current_id, get_chain_fn, visited) do
    if MapSet.member?(visited, current_id) do
      false
    else
      chain = get_chain_fn.(current_id)
      visited = MapSet.put(visited, current_id)

      Enum.any?(chain, fn entry ->
        entry.backup_agent_id == agent_id or
          do_cycle_check(agent_id, entry.backup_agent_id, get_chain_fn, visited)
      end)
    end
  end
end
