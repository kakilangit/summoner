defmodule SummonerWeb.AdminLive.InvitationIndex do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Invitations
  alias Summoner.Domain.Schemas.Invitation

  @sort_options [{"Created", :inserted_at}, {"Expires", :expires_at}, {"Code", :code}]
  @default_sort_by :inserted_at
  @default_sort_dir :desc
  @filter_fields [:code]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Admin — Invites",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_dir =
      if socket.assigns.sort_by == field,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :asc

    {:noreply, socket |> assign(sort_by: field, sort_dir: sort_dir) |> load_page()}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(filter: filter) |> load_page()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">All Invites</h1>
        <.link navigate="/archon" class="btn btn-ghost btn-sm">Back to Dashboard</.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search by code..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No summons yet.</p>
        <p :if={@filter != ""}>No summons match your search.</p>
      </div>

      <div :if={@page.entries != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Code</th>
              <th>Status</th>
              <th>Guild</th>
              <th>Created By</th>
              <th>Used By</th>
              <th>Expires</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={inv <- @page.entries} class="hover">
              <td>
                <code class="text-xs">{inv.code}</code>
              </td>
              <td>
                <.invitation_badge invitation={inv} />
              </td>
              <td class="text-sm">
                {if inv.tenant, do: inv.tenant.name, else: "—"}
              </td>
              <td class="text-sm">{inv.invited_by.email}</td>
              <td class="text-sm">{if inv.used_by, do: inv.used_by.email, else: "—"}</td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(inv.expires_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(inv.inserted_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp invitation_badge(assigns) do
    status = Invitation.status(assigns.invitation)
    assigns = assign(assigns, :status, status)

    ~H"""
    <span :if={@status == :available} class="badge badge-sm badge-success">Available</span>
    <span :if={@status == :used} class="badge badge-sm badge-info">Used</span>
    <span :if={@status == :expired} class="badge badge-sm badge-error">Expired</span>
    """
  end

  defp load_page(socket) do
    assign(socket, page: Invitations.list_all_invitations(list_opts(socket.assigns)))
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
