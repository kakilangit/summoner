defmodule SummonerWeb.ApprovalLive.Pending do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Approvals

  @sort_options [{"Created", :inserted_at}, {"Summary", :action_summary}]
  @default_sort_by :inserted_at
  @default_sort_dir :desc
  @filter_fields [:action_summary]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Pending Rites - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Pending Rites", nil}
        ]
      )
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_dir =
      if socket.assigns.sort_by == field,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :asc

    {:noreply, socket |> assign(sort_by: field, sort_dir: sort_dir) |> load_page()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter) |> load_page()}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    decide(socket, id, "approved")
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    decide(socket, id, "rejected")
  end

  defp decide(socket, id, decision) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    approval = Approvals.get_pending!(scope, workspace.id, id)
    user_id = socket.assigns.current_scope.user.id

    case Approvals.decide(approval, decision, user_id) do
      {:ok, _} ->
        label = if decision == "approved", do: "approved", else: "rejected"
        {:noreply, socket |> load_page() |> put_flash(:info, "Action #{label}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record decision.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Pending Rites</h1>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search pending rites..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>
          No pending approvals. Agent actions will appear here when they trigger a rite.
        </p>
        <p :if={@filter != ""}>No pending rites match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={approval <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/pending-approvals/#{approval.id}"
                }
                class="font-medium link link-hover"
              >
                {approval.action_summary}
              </.link>
              <span class="badge badge-warning badge-xs">{approval.status}</span>
            </div>
            <div class="text-sm text-base-content/60">
              <span :if={approval.agent}>Agent: {approval.agent.name}</span>
              <span :if={approval.rule}>· Rule: {approval.rule.name}</span>
              <span>· {Calendar.strftime(approval.inserted_at, "%Y-%m-%d %H:%M:%S")}</span>
            </div>
          </div>
          <div :if={approval.status == "pending"} class="flex gap-2 flex-shrink-0">
            <button
              phx-click="approve"
              phx-value-id={approval.id}
              class="btn btn-success btn-sm"
            >
              Approve
            </button>
            <button
              phx-click="reject"
              phx-value-id={approval.id}
              class="btn btn-error btn-sm btn-outline"
            >
              Reject
            </button>
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns
    opts = list_opts(socket.assigns)
    page = Approvals.list_pending_paginated(scope, workspace.id, opts)
    assign(socket, page: page)
  end

  defp list_opts(assigns) do
    [
      page: Map.get(assigns, :page_num, assigns[:page] && assigns.page.page) || 1,
      sort_by: assigns.sort_by,
      sort_dir: assigns.sort_dir,
      filter: assigns.filter,
      filter_fields: @filter_fields
    ]
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc
end
