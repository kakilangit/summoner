defmodule SummonerWeb.ApprovalLive.Show do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Approvals

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    approval = Approvals.get_pending!(scope, workspace.id, id)

    socket =
      socket
      |> assign(
        page_title: "Pending Rite - #{workspace.name}",
        approval: approval,
        decision_note: ""
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Pending Rites",
           ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}/pending-approvals"},
          {approval.action_summary, nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("update_note", %{"decision_note" => note}, socket) do
    {:noreply, assign(socket, decision_note: note)}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    decide(socket, "approved")
  end

  @impl true
  def handle_event("reject", _params, socket) do
    decide(socket, "rejected")
  end

  defp decide(socket, decision) do
    approval = socket.assigns.approval
    user_id = socket.assigns.current_scope.user.id
    note = socket.assigns.decision_note

    note_arg = if note == "", do: nil, else: note

    case Approvals.decide(approval, decision, user_id, note_arg) do
      {:ok, updated} ->
        label = if decision == "approved", do: "approved", else: "rejected"

        {:noreply,
         socket
         |> assign(approval: updated)
         |> put_flash(:info, "Action #{label}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record decision.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Pending Rite</h1>

      <div class="space-y-4">
        <div class="p-4 bg-base-200 rounded-lg space-y-3">
          <div>
            <span class="text-sm text-base-content/60">Summary</span>
            <p class="font-medium">{@approval.action_summary}</p>
          </div>

          <div>
            <span class="text-sm text-base-content/60">Status</span>
            <p>
              <span class={[
                "badge badge-sm",
                @approval.status == "pending" && "badge-warning",
                @approval.status == "approved" && "badge-success",
                @approval.status == "rejected" && "badge-error",
                @approval.status == "expired" && "badge-neutral"
              ]}>
                {@approval.status}
              </span>
            </p>
          </div>

          <div :if={@approval.agent}>
            <span class="text-sm text-base-content/60">Agent</span>
            <p>{@approval.agent.name}</p>
          </div>

          <div :if={@approval.rule}>
            <span class="text-sm text-base-content/60">Rule</span>
            <p>{@approval.rule.name} ({@approval.rule.trigger_type})</p>
          </div>

          <div>
            <span class="text-sm text-base-content/60">Created</span>
            <p>{Calendar.strftime(@approval.inserted_at, "%Y-%m-%d %H:%M:%S")}</p>
          </div>

          <div :if={@approval.action_details != %{}}>
            <span class="text-sm text-base-content/60">Action Details</span>
            <pre class="mt-1 p-3 bg-base-300 rounded text-sm overflow-x-auto"><code>{Jason.encode!(@approval.action_details, pretty: true)}</code></pre>
          </div>
        </div>

        <div
          :if={@approval.status != "pending"}
          class="p-4 bg-base-200 rounded-lg space-y-3"
        >
          <div :if={@approval.decided_at}>
            <span class="text-sm text-base-content/60">Decided At</span>
            <p>{Calendar.strftime(@approval.decided_at, "%Y-%m-%d %H:%M:%S")}</p>
          </div>
          <div :if={@approval.decision_note}>
            <span class="text-sm text-base-content/60">Decision Note</span>
            <p>{@approval.decision_note}</p>
          </div>
        </div>

        <div :if={@approval.status == "pending"} class="p-4 bg-base-200 rounded-lg space-y-4">
          <div>
            <label class="label">
              <span class="label-text">Decision Note (optional)</span>
            </label>
            <textarea
              phx-change="update_note"
              name="decision_note"
              class="textarea textarea-bordered w-full"
              placeholder="Reason for your decision..."
              phx-debounce="300"
            >{@decision_note}</textarea>
          </div>
          <div class="flex items-center gap-4">
            <button phx-click="approve" class="btn btn-success btn-sm">
              Approve
            </button>
            <button phx-click="reject" class="btn btn-error btn-sm btn-outline">
              Reject
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
