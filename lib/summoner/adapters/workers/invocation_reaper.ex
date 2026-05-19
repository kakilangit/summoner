defmodule Summoner.Adapters.Workers.InvocationReaper do
  @moduledoc """
  Periodic Oban worker that finds orphaned invocations (running but with no
  live Agent GenServer or exceeded total_timeout_s) and transitions them
  back to queued.

  Pipeline invocations (those with `pipeline_id` set) are excluded because
  their lifecycle is managed by `PipelineRunnerJob`, not an AgentServer.
  """

  use Oban.Worker, queue: :reaper, max_attempts: 1

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Orchestration
  alias Summoner.Domain.Schemas.Invocation
  alias Summoner.Repo

  @registry Summoner.AgentRegistry

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    running_invocations()
    |> Enum.each(&maybe_reap/1)

    :ok
  end

  defp running_invocations do
    Invocation
    |> where([i], i.status == :running and is_nil(i.pipeline_id))
    |> preload(agent: :local_agent)
    |> Repo.all()
  end

  defp maybe_reap(%Invocation{} = invocation) do
    cond do
      timed_out?(invocation) ->
        requeue(invocation, :timeout)

      no_live_server?(invocation) ->
        requeue(invocation, :orphaned)

      true ->
        :ok
    end
  end

  defp timed_out?(%Invocation{started_at: nil}), do: false

  defp timed_out?(%Invocation{started_at: started_at, agent: agent}) do
    timeout_s =
      if agent && agent.local_agent, do: agent.local_agent.total_timeout_s || 300, else: 300

    deadline = DateTime.add(started_at, timeout_s, :second)
    DateTime.compare(DateTime.utc_now(), deadline) == :gt
  end

  defp no_live_server?(%Invocation{} = invocation) do
    case Registry.lookup(@registry, {invocation.workspace_id, invocation.agent_id}) do
      [] -> true
      _pids -> false
    end
  end

  defp requeue(%Invocation{} = invocation, reason) do
    Orchestration.update_invocation_status(invocation, :queued, %{
      end_reason: nil,
      started_at: nil,
      completed_at: nil
    })

    Orchestration.add_event(%{
      invocation_id: invocation.id,
      workspace_id: invocation.workspace_id,
      event_type: :reaper,
      payload: %{reason: reason, reaped_at: DateTime.utc_now()}
    })
  end
end
