defmodule Summoner.Services.Orchestration.Dispatcher do
  @moduledoc """
  Manages the lifecycle of a single subtask: assignment, monitoring,
  timeout enforcement, and completion bookkeeping.

  Each Dispatcher runs as a supervised Task under `Task.Supervisor`.
  It is spawned by the delegating agent's GenServer for each ready subtask.

  ## Lifecycle

  1. Offer the subtask to the target worker via `GenServer.call`.
  2. On successful claim, monitor the worker GenServer.
  3. Wait for `{:task_result, subtask_id, status, result}` or timeout.
  4. On completion, evaluate acceptance criteria (if present).
  5. Report result back to the delegating agent.
  """

  require Logger

  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Domain.Schemas.Subtask
  alias Summoner.Services.Agents.Server, as: AgentServer

  @task_offer_timeout 10_000
  @default_subtask_timeout_s 300

  @doc """
  Dispatches a subtask to a worker agent.

  Called within a `Task.Supervisor.async_nolink` from the manager's GenServer.
  Returns `{:ok, subtask_id, :completed | :failed, result}` or
  `{:error, subtask_id, reason}`.
  """
  def dispatch(%Subtask{} = subtask, manager_state) do
    workspace_id = manager_state.agent.workspace_id
    target_agent_id = subtask.assigned_agent_id

    with :ok <- AgentServer.ensure_started(workspace_id, target_agent_id),
         {:ok, worker_invocation_id} <- offer_to_worker(workspace_id, target_agent_id, subtask),
         {:ok, claimed} <- claim(subtask, target_agent_id, worker_invocation_id) do
      notify_subtask_started(manager_state, claimed)
      monitor_and_wait(claimed, workspace_id, target_agent_id, manager_state)
    else
      {:error, reason} ->
        Logger.warning("Subtask #{subtask.id} dispatch failed: #{inspect(reason)}")
        {:error, subtask.id, reason}
    end
  end

  defp offer_to_worker(workspace_id, agent_id, subtask) do
    GenServer.call(
      AgentServer.via(workspace_id, agent_id),
      {:task_offer, subtask.id, subtask.description, subtask.invocation_id},
      @task_offer_timeout
    )
  catch
    :exit, {:timeout, _} -> {:error, :offer_timeout}
    :exit, reason -> {:error, {:worker_exit, reason}}
  end

  defp claim(subtask, agent_id, worker_invocation_id) do
    Orchestration.claim_subtask(subtask.id, agent_id, worker_invocation_id)
  end

  defp notify_subtask_started(%{on_subtask_started: cb}, subtask)
       when is_function(cb, 1),
       do: cb.(subtask)

  defp notify_subtask_started(_, _), do: :ok

  defp monitor_and_wait(subtask, workspace_id, agent_id, manager_state) do
    timeout_s = manager_state.agent.local_agent.total_timeout_s || @default_subtask_timeout_s
    timeout_ms = timeout_s * 1_000
    ref = monitor_worker(workspace_id, agent_id)

    result = wait_for_result(subtask, ref, timeout_ms)

    if ref, do: Process.demonitor(ref, [:flush])

    finalize_subtask(subtask, result)
  end

  defp monitor_worker(workspace_id, agent_id) do
    case GenServer.whereis(AgentServer.via(workspace_id, agent_id)) do
      nil -> nil
      pid -> Process.monitor(pid)
    end
  end

  defp finalize_subtask(subtask, {:completed, output}) do
    {:ok, _} = Orchestration.complete_subtask(subtask)
    {:ok, subtask.id, :completed, output}
  end

  defp finalize_subtask(subtask, {:failed, reason}) do
    {:ok, _} = Orchestration.fail_subtask(subtask)
    {:ok, subtask.id, :failed, reason}
  end

  defp finalize_subtask(subtask, {:timeout, _}) do
    {:ok, _} = Orchestration.fail_subtask(subtask)
    {:ok, subtask.id, :failed, :timeout}
  end

  defp finalize_subtask(subtask, {:worker_down, reason}) do
    Logger.warning("Worker DOWN for subtask #{subtask.id}: #{inspect(reason)}")
    {:ok, _} = Orchestration.fail_subtask(subtask)
    {:error, subtask.id, :worker_down}
  end

  defp wait_for_result(subtask, monitor_ref, timeout_ms) do
    receive do
      {:task_result, subtask_id, :ok, result} when subtask_id == subtask.id ->
        {:completed, result}

      {:task_result, subtask_id, :error, result} when subtask_id == subtask.id ->
        {:failed, result}

      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        {:worker_down, reason}
    after
      timeout_ms ->
        {:timeout, :subtask_timeout}
    end
  end
end
