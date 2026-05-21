defmodule SummonerWeb.AdminLive.WorkspaceIndex do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Admin

  @sort_options [{"Name", :name}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Admin — Realms",
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

  def handle_event("delete", %{"id" => id}, socket) do
    workspace = Admin.get_workspace!(id)

    case Admin.delete_workspace(workspace) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Realm deleted.") |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete realm.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Realms</h1>
        <.link navigate="/admin" class="btn btn-ghost btn-sm">Back to Dashboard</.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search realms..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No realms yet.</p>
        <p :if={@filter != ""}>No realms match your search.</p>
      </div>

      <div :if={@page.entries != []} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Name</th>
              <th>Guild</th>
              <th>Members</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={workspace <- @page.entries} class="hover">
              <td>
                <.link
                  navigate={~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"}
                  class="link link-hover font-medium"
                >
                  {workspace.name}
                </.link>
              </td>
              <td>
                <.link
                  navigate={~p"/tenants/#{workspace.tenant_id}/workspaces"}
                  class="link link-hover text-sm"
                >
                  {workspace.tenant.name}
                </.link>
              </td>
              <td>{Admin.member_count(workspace)}</td>
              <td class="text-xs text-base-content/60">
                {Summoner.Services.TimeZone.format(workspace.inserted_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
              <td>
                <button
                  phx-click="delete"
                  phx-value-id={workspace.id}
                  class="btn btn-ghost btn-xs btn-error"
                  data-confirm="Delete this realm and all its data? This cannot be undone."
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    assign(socket, page: Admin.list_workspaces(list_opts(socket.assigns)))
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
