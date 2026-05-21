defmodule Summoner.Services.Orchestration.AgentFailover do
  @moduledoc """
  Service-level failover orchestration.

  Uses the pure `Domain.Policies.Failover` for decisions, then
  walks the agent's failover chain to resolve the next active backup
  agent via ports and publishes domain events.
  """

  require Logger

  alias Summoner.Domain.Events.Failover, as: FailoverEvent
  alias Summoner.Domain.Policies.Failover, as: FailoverPolicy
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Orchestration

  @doc """
  Handles a failed invocation by consulting the failover policy,
  then walking the agent's failover chain to find the next active backup.

  Returns:
  - `{:failover, backup_agent, depth}` — caller should start new invocation with backup
  - `{:failover_delayed, backup_agent, delay_ms, depth}` — caller should delay then failover
  - `{:failover_pending, backup_agent_id}` — waiting for manual approval
  - `:no_failover` — no failover possible (no backup, exhausted, or error not eligible)
  """
  def handle(agent, invocation, error) do
    current_depth = invocation.failover_depth || 0

    case FailoverPolicy.handle_failure(agent, error, current_depth) do
      {:failover, :auto} ->
        resolve_and_execute(agent, invocation, error, current_depth)

      {:failover_delayed, delay_ms} ->
        resolve_for_delayed(agent, delay_ms, current_depth)

      :failover_pending ->
        resolve_for_pending(agent)

      _other ->
        :no_failover
    end
  end

  # --- Private ---

  defp resolve_for_delayed(agent, delay_ms, current_depth) do
    case resolve_next_backup(agent) do
      {:ok, backup_agent} -> {:failover_delayed, backup_agent, delay_ms, current_depth + 1}
      :exhausted -> :no_failover
    end
  end

  defp resolve_for_pending(agent) do
    case resolve_next_backup(agent) do
      {:ok, backup_agent} -> {:failover_pending, backup_agent.id}
      :exhausted -> :no_failover
    end
  end

  @doc """
  Validates that adding `backup_agent_id` to `agent_id`'s failover chain
  won't create a cycle. Builds the lookup from the database.
  """
  def validate_no_cycle(agent_id, backup_agent_id, workspace_id) do
    get_chain_fn = fn id ->
      scope = %{user: nil}

      try do
        agent = Agents.get_agent!(scope, workspace_id, id)
        agent.failover_chain || []
      rescue
        Ecto.NoResultsError -> []
      end
    end

    if FailoverPolicy.creates_cycle?(agent_id, backup_agent_id, get_chain_fn) do
      {:error, :circular_failover_chain}
    else
      :ok
    end
  end

  defp resolve_and_execute(agent, invocation, error, current_depth) do
    case resolve_next_backup(agent) do
      {:ok, backup_agent} ->
        execute_failover(agent, invocation, backup_agent, error, current_depth)

      :exhausted ->
        :no_failover
    end
  end

  defp resolve_next_backup(agent) do
    chain = agent.failover_chain || []

    chain
    |> Enum.sort_by(& &1.position)
    |> Enum.reduce_while(:exhausted, fn entry, _acc ->
      case resolve_backup(entry.backup_agent_id) do
        {:ok, backup_agent} -> {:halt, {:ok, backup_agent}}
        :skip -> {:cont, :exhausted}
      end
    end)
  end

  defp execute_failover(agent, invocation, backup_agent, error, current_depth) do
    new_depth = current_depth + 1
    reason = format_reason(error)

    # Mark original invocation as failed with failover
    Orchestration.update_invocation_status(invocation, :failed, %{
      end_reason: :failover,
      output: %{"failover_to" => backup_agent.id, "error" => reason},
      completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })

    # Publish failover event
    Events.publish(%FailoverEvent{
      invocation_id: invocation.id,
      from_agent_id: agent.id,
      to_agent_id: backup_agent.id,
      reason: reason,
      depth: new_depth,
      workspace_id: invocation.workspace_id
    })

    Logger.warning(
      "Failover: @#{agent.callname} → @#{backup_agent.callname} " <>
        "(depth #{new_depth}): #{reason}"
    )

    {:failover, backup_agent, new_depth}
  end

  defp resolve_backup(backup_agent_id) do
    agent = Agents.get_agent_with_provider!(backup_agent_id)
    {:ok, agent}
  rescue
    Ecto.NoResultsError ->
      Logger.warning("Backup agent #{backup_agent_id} not found (deleted?), skipping")
      :skip
  end

  defp format_reason({:api_error, status, body}) do
    "HTTP #{status}: #{inspect(body)}"
  end

  defp format_reason({error_type, details}) do
    "#{error_type}: #{inspect(details)}"
  end

  defp format_reason(error) do
    inspect(error)
  end
end
