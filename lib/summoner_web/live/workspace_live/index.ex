defmodule SummonerWeb.WorkspaceLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Adapters.Persistence.Workspaces

  @sort_options [{"Name", :name}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Realms",
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

  defp load_page(socket) do
    scope = socket.assigns.current_scope
    opts = list_opts(socket.assigns)

    page =
      if tenant = socket.assigns[:tenant] do
        Workspaces.list_workspaces_for_user_in_tenant_paginated(scope, tenant.id, opts)
      else
        Workspaces.list_workspaces_for_user_paginated(scope, opts)
      end

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Realms</h1>
        <.link
          :if={assigns[:tenant]}
          navigate={~p"/guilds/#{@tenant.id}/realms/new"}
          class="btn btn-primary btn-sm"
        >
          New Realm
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search realms..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No realms yet. Create one to get started.</p>
        <p :if={@filter != ""}>No realms match your search.</p>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={workspace <- @page.entries}
          navigate={~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"}
          class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">{workspace.name}</h2>
            <p class="text-sm text-base-content/60">
              Context window: {workspace.settings.context_window_messages} messages
            </p>
          </div>
        </.link>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end
end
