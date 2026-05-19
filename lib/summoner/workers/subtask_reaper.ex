defmodule Summoner.Workers.SubtaskReaper do
  @moduledoc """
  Periodic Oban worker (every 30s) that finds stuck subtasks.

  A subtask is stuck if:
  - Status is `running` and the worker's invocation has no live GenServer
    or has been running longer than `total_timeout_s`.

  Stuck subtasks are requeued to `pending` (incrementing retry_count).
  If retry_count exceeds the budget (1), the subtask is marked `failed`.
  """

  use Oban.Worker, queue: :reaper, max_attempts: 1

  import Ecto.Query, warn: false

  alias Summoner.Orchestration
  alias Summoner.Orchestration.Subtask
  alias Summoner.Repo

  @registry Summoner.AgentRegistry
  @max_retries 1
  @default_timeout_s 300

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    claimed_subtasks()
    |> Enum.each(&maybe_reap/1)

    :ok
  end

  defp claimed_subtasks do
    Subtask
    |> where([s], s.status == :running)
    |> preload(invocation: [agent: :local_agent])
    |> Repo.all()
  end

  defp maybe_reap(%Subtask{} = subtask) do
    cond do
      timed_out?(subtask) -> reap(subtask)
      no_live_worker?(subtask) -> reap(subtask)
      true -> :ok
    end
  end

  defp timed_out?(%Subtask{updated_at: updated_at, invocation: inv}) do
    timeout_s =
      if inv.agent && inv.agent.local_agent,
        do: inv.agent.local_agent.total_timeout_s || @default_timeout_s,
        else: @default_timeout_s

    deadline = DateTime.add(updated_at, timeout_s, :second)
    DateTime.compare(DateTime.utc_now(), deadline) == :gt
  end

  defp no_live_worker?(%Subtask{assigned_agent_id: nil}), do: true

  defp no_live_worker?(%Subtask{assigned_agent_id: agent_id, invocation: inv}) do
    case Registry.lookup(@registry, {inv.workspace_id, agent_id}) do
      [] -> true
      _pids -> false
    end
  end

  defp reap(%Subtask{retry_count: count} = subtask) when count >= @max_retries do
    Orchestration.fail_subtask(subtask)
  end

  defp reap(%Subtask{} = subtask) do
    Orchestration.requeue_subtask(subtask)
  end
end
