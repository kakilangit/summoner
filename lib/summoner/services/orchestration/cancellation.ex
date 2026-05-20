defmodule Summoner.Services.Orchestration.Cancellation do
  @moduledoc """
  Cascading cancellation of invocations across the delegation tree.

  When a user cancels an invocation, all descendant invocations
  (via `parent_invocation_id` traversal) are also cancelled.
  Each affected GenServer receives a `{:cancel, invocation_id}` message.

  In-flight tool calls are allowed to complete (to avoid leaving
  external state inconsistent) but their results are discarded.
  """

  alias Summoner.Domain.Schemas.Invocation
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Services.Agents.Server, as: AgentServer

  @doc """
  Cancels an invocation and all its descendants.

  Returns `{:ok, cancelled_count}`.
  """
  def cancel_tree(invocation_id) do
    invocation = Orchestration.get_invocation_by_id(invocation_id)

    if invocation do
      ids = collect_descendants(invocation_id) ++ [invocation_id]
      cancel_all(ids)
      {:ok, length(ids)}
    else
      {:error, :not_found}
    end
  end

  defp collect_descendants(parent_id) do
    children = Orchestration.active_child_invocation_ids(parent_id)

    children ++ Enum.flat_map(children, &collect_descendants/1)
  end

  defp cancel_all(invocation_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Enum.each(invocation_ids, fn id ->
      case Orchestration.get_invocation_by_id(id) do
        %Invocation{status: status} = inv when status not in [:completed, :failed, :cancelled] ->
          {:ok, _} =
            Orchestration.update_invocation_status(inv, :cancelled, %{
              end_reason: :cancelled,
              completed_at: now
            })

          # Notify the agent GenServer
          notify_agent(inv)

        _ ->
          :ok
      end
    end)
  end

  defp notify_agent(%Invocation{workspace_id: workspace_id, agent_id: agent_id} = inv) do
    case GenServer.whereis(AgentServer.via(workspace_id, agent_id)) do
      nil -> :ok
      pid -> send(pid, {:cancel, inv.id})
    end
  end
end
