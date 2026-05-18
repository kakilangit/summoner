defmodule SummonerWeb.TenantLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Accounts.Scope
  alias Summoner.Admin
  alias Summoner.Tenants

  @sort_options [{"Name", :name}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.admin?(scope) do
      socket =
        socket
        |> assign(
          page_title: "Guilds",
          is_admin: true,
          sort_by: @default_sort_by,
          sort_dir: @default_sort_dir,
          filter: "",
          sort_options: @sort_options
        )
        |> load_page()

      {:ok, socket}
    else
      tenants = Tenants.list_tenants_for_user(scope)

      case tenants do
        [single] ->
          {:ok, push_navigate(socket, to: ~p"/realms/#{single.id}/realms")}

        _ ->
          socket =
            socket
            |> assign(page_title: "Guilds", is_admin: false, tenants: tenants)

          {:ok, socket}
      end
    end
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

  def handle_event("disable", %{"id" => id}, socket) do
    tenant = Admin.get_tenant!(id)

    case Admin.disable_tenant(tenant) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Guild disabled.") |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to disable realm.")}
    end
  end

  def handle_event("enable", %{"id" => id}, socket) do
    tenant = Admin.get_tenant!(id)

    case Admin.enable_tenant(tenant) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Guild enabled.") |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to enable realm.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = Admin.get_tenant!(id)

    case Admin.delete_tenant(tenant) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Guild deleted.") |> load_page()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete realm.")}
    end
  end

  @impl true
  def render(assigns) do
    if assigns.is_admin do
      render_admin(assigns)
    else
      render_user(assigns)
    end
  end

  defp render_user(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Guilds</h1>
      </div>

      <div :if={@tenants == []} class="text-center py-12 text-base-content/60">
        <p>No realms available. Contact your administrator.</p>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={tenant <- @tenants}
          navigate={~p"/realms/#{tenant.id}/realms"}
          class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">{tenant.name}</h2>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  defp render_admin(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Guilds</h1>
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
              <th>Members</th>
              <th>Guilds</th>
              <th>Status</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={tenant <- @page.entries} class="hover">
              <td>
                <.link
                  navigate={~p"/realms/#{tenant.id}/realms"}
                  class="link link-hover font-medium"
                >
                  {tenant.name}
                </.link>
              </td>
              <td>{Admin.tenant_member_count(tenant)}</td>
              <td>{Admin.tenant_workspace_count(tenant)}</td>
              <td>
                <span :if={is_nil(tenant.disabled_at)} class="badge badge-success badge-sm">
                  Active
                </span>
                <span :if={tenant.disabled_at} class="badge badge-error badge-sm">Disabled</span>
              </td>
              <td class="text-xs text-base-content/60">
                {Summoner.TimeZone.format(tenant.inserted_at,
                  format: "%Y-%m-%d",
                  show_zone: false
                )}
              </td>
              <td class="flex gap-1">
                <.link
                  navigate={~p"/realms/#{tenant.id}/edit"}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </.link>
                <button
                  :if={is_nil(tenant.disabled_at)}
                  phx-click="disable"
                  phx-value-id={tenant.id}
                  class="btn btn-ghost btn-xs"
                >
                  Disable
                </button>
                <button
                  :if={tenant.disabled_at}
                  phx-click="enable"
                  phx-value-id={tenant.id}
                  class="btn btn-ghost btn-xs"
                >
                  Enable
                </button>
                <button
                  phx-click={show_confirm("#delete-tenant-#{tenant.id}")}
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
                <.confirm_modal
                  id={"delete-tenant-#{tenant.id}"}
                  title="Delete realm?"
                  message="This realm and all its data will be permanently removed. This cannot be undone."
                  on_confirm={JS.push("delete", value: %{id: tenant.id})}
                />
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
    assign(socket, page: Admin.list_tenants(list_opts(socket.assigns)))
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
