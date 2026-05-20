defmodule Summoner.Services.Orchestration.FailurePolicy do
  @moduledoc """
  Handles failure decisions for subtasks that exhaust their retry budget.

  When a subtask fails after its retry budget (1 attempt), the manager
  must choose one of:
  - `:skip` — mark the subtask as skipped, continue with partial results
  - `:abort` — fail the entire invocation with an error summary
  - `:escalate` — pause the invocation and request user intervention

  The default policy is `:abort` — fail the invocation on any subtask failure.
  Future phases may add LLM-based decision-making.
  """

  require Logger

  alias Summoner.Ports.Persistence.Audit
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Domain.Events.Escalation
  alias Summoner.Domain.Schemas.Subtask
  alias Summoner.Ports.Events

  @max_retries 1

  @doc """
  Checks whether a failed subtask can be retried.
  """
  def can_retry?(%Subtask{retry_count: count}), do: count < @max_retries

  @doc """
  Applies the failure policy for a subtask that has exhausted retries.

  `action` is one of `:skip`, `:abort`, or `:escalate`.
  `invocation` is the manager's invocation.
  `subtask` is the failed subtask.

  Returns `{:ok, action_taken}` or `{:error, reason}`.
  """
  def apply_policy(:skip, _invocation, %Subtask{} = subtask) do
    {:ok, _} = Orchestration.skip_subtask(subtask)
    {:ok, :skipped}
  end

  def apply_policy(:abort, invocation, %Subtask{} = subtask) do
    {:ok, _} =
      Orchestration.update_invocation_status(invocation, :failed, %{
        end_reason: :failed,
        output: %{
          "error" => "Subtask failed",
          "subtask_id" => subtask.id,
          "description" => subtask.description
        },
        completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    {:ok, :aborted}
  end

  def apply_policy(:escalate, invocation, %Subtask{} = subtask) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    # Set invocation to awaiting_user
    {:ok, _} =
      Orchestration.update_invocation_status(invocation, :awaiting_user, %{})

    # Write invocation event
    {:ok, _} =
      Orchestration.add_event(%{
        invocation_id: invocation.id,
        agent_id: invocation.agent_id,
        event_type: :awaiting_user,
        visibility: :public,
        summary: "Subtask failed — awaiting user decision",
        payload: %{
          "subtask_id" => subtask.id,
          "description" => subtask.description,
          "escalated_at" => DateTime.to_iso8601(now)
        }
      })

    # Write audit log
    Audit.log(%{
      workspace_id: invocation.workspace_id,
      action: "escalation",
      agent_id: invocation.agent_id,
      detail: %{
        "invocation_id" => invocation.id,
        "subtask_id" => subtask.id,
        "reason" => "Subtask exhausted retry budget"
      }
    })

    # Broadcast escalation
    Events.publish(%Escalation{
      workspace_id: invocation.workspace_id,
      invocation_id: invocation.id,
      reason: "Subtask failed: #{subtask.description}"
    })

    {:ok, :escalated}
  end
end
