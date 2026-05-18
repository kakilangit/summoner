defmodule SummonerWeb.TenantMcpServerLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.MCP

  @sort_options [{"Name", :name}, {"Transport", :transport}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name, :command_or_url]

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.tenant

    socket =
      socket
      |> assign(
        page_title: "Runes - #{tenant.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Guilds", ~p"/guilds"},
          {tenant.name, ~p"/realms/#{tenant.id}/realms"},
          {"Runes", nil}
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
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.tenant_can?.(:manage_resources) do
      do_delete(socket, id)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end

  defp do_delete(socket, id) do
    tenant = socket.assigns.tenant
    server = MCP.get_tenant_server!(tenant.id, id)

    case MCP.delete_server(socket.assigns.current_scope, server) do
      {:ok, _} ->
        {:noreply, socket |> load_page() |> put_flash(:info, "Rune deleted.")}

      {:error, changeset} ->
        message =
          case changeset.errors[:agent_mcp_servers] do
            {msg, _} -> "Cannot delete rune: #{msg}."
            _ -> "Could not delete rune."
          end

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Runes</h1>
        <.link
          :if={@tenant_can?.(:manage_resources)}
          navigate={~p"/realms/#{@tenant.id}/runes/new"}
          class="btn btn-primary btn-sm"
        >
          New Rune
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search runes..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>
          No realm runes configured. Add one to share tools across sanctums.
        </p>
        <p :if={@filter != ""}>No runes match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={server <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="font-medium">{server.name}</span>
              <span class={[
                "badge badge-sm",
                server.transport == :stdio && "badge-info",
                server.transport == :http && "badge-warning"
              ]}>
                {server.transport}
              </span>
            </div>
            <div class="text-sm text-base-content/60 font-mono truncate max-w-md">
              {server.command_or_url}
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              :if={@tenant_can?.(:manage_resources)}
              navigate={~p"/realms/#{@tenant.id}/runes/#{server.id}/edit"}
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@tenant_can?.(:manage_resources)}
              phx-click={show_confirm("#delete-mcp-#{server.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@tenant_can?.(:manage_resources)}
              id={"delete-mcp-#{server.id}"}
              title="Delete rune?"
              message="This rune will be permanently removed. Summons using it will lose access to its tools."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: server.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    tenant = socket.assigns.tenant
    opts = list_opts(socket.assigns)
    page = MCP.list_tenant_servers_paginated(tenant.id, opts)
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
