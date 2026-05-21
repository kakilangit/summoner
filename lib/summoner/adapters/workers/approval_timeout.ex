defmodule Summoner.Adapters.Workers.ApprovalTimeout do
  @moduledoc """
  Periodic Oban worker that checks for expired pending approvals
  and applies their timeout action (approve, reject, or escalate).

  Runs every 60 seconds.
  """

  use Oban.Worker, queue: :reaper, max_attempts: 1

  require Logger

  alias Summoner.Ports.Persistence.Approvals
  alias Summoner.Ports.Persistence.Orchestration

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    Approvals.list_expired(now)
    |> Enum.each(fn approval ->
      timeout_s = approval.rule.timeout_s || 3600
      deadline = DateTime.add(approval.inserted_at, timeout_s, :second)

      if DateTime.compare(now, deadline) == :gt do
        handle_timeout(approval)
      end
    end)

    :ok
  end

  defp handle_timeout(approval) do
    timeout_action = approval.rule.timeout_action || "reject"

    Logger.info("Approval #{approval.id} timed out, applying action: #{timeout_action}")

    case timeout_action do
      "approve" ->
        Approvals.decide(approval, "approved", nil, "Auto-approved: timeout expired")
        resume_invocation(approval.invocation_id)

      "reject" ->
        Approvals.decide(approval, "rejected", nil, "Auto-rejected: timeout expired")
        fail_invocation(approval.invocation_id)

      "escalate" ->
        Approvals.decide(approval, "expired", nil, "Escalated: timeout expired")
        fail_invocation(approval.invocation_id)

      _ ->
        Approvals.decide(approval, "expired", nil, "Timeout expired")
        fail_invocation(approval.invocation_id)
    end
  end

  defp resume_invocation(_invocation_id) do
    # Re-queuing invocations from paused state requires the full ReactLoop
    # context which is not available here. The invocation will be picked up
    # by the InvocationReaper which handles stale states.
    :ok
  end

  defp fail_invocation(invocation_id) do
    Orchestration.update_invocation_status_by_id(invocation_id, :failed, %{
      end_reason: :approval_rejected,
      output: %{"error" => "approval_timeout"}
    })
  end
end
