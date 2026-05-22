defmodule SummonerWeb.PluginLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Services.Plugins

  @sort_options [{"Name", :name}, {"Status", :status}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Grimoires - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Grimoires", nil}
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
  def handle_event("enable", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace

      case Plugins.enable(workspace.id, id) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Grimoire enabled.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Enable failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("disable", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace

      case Plugins.disable(workspace.id, id) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Grimoire disabled.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Disable failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def handle_event("uninstall", %{"id" => id}, socket) do
    authorize(socket, :configure, fn ->
      workspace = socket.assigns.workspace

      case Plugins.uninstall(workspace.id, id) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Grimoire uninstalled.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Uninstall failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Grimoires</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/plugins/install"}
          class="btn btn-primary btn-sm"
        >
          Install Grimoire
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search grimoires..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No grimoires installed. Install one to extend your realm.</p>
        <p :if={@filter != ""}>No grimoires match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={plugin <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/plugins/#{plugin.id}"
                }
                class="font-medium hover:underline"
              >
                {plugin.name}
              </.link>
              <span class={[
                "badge badge-sm",
                status_badge_class(plugin.status)
              ]}>
                {plugin.status}
              </span>
            </div>
            <div class="flex items-center gap-1 mt-1">
              <span :for={cap <- plugin.capabilities} class="badge badge-ghost badge-xs">
                {cap}
              </span>
            </div>
            <div :if={plugin.error_message} class="text-sm text-error mt-1 truncate max-w-md">
              {plugin.error_message}
            </div>
          </div>
          <div :if={@can?.(:configure)} class="flex gap-2 flex-shrink-0">
            <button
              :if={plugin.status in [:installed, :disabled, :error]}
              phx-click="enable"
              phx-value-id={plugin.id}
              class="btn btn-success btn-sm btn-outline"
            >
              Enable
            </button>
            <button
              :if={plugin.status == :enabled}
              phx-click="disable"
              phx-value-id={plugin.id}
              class="btn btn-warning btn-sm btn-outline"
            >
              Disable
            </button>
            <button
              phx-click={show_confirm("#uninstall-#{plugin.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Uninstall
            </button>
            <.confirm_modal
              id={"uninstall-#{plugin.id}"}
              title="Uninstall grimoire?"
              message={"#{plugin.name} will be permanently removed."}
              confirm_text="Uninstall"
              on_confirm={JS.push("uninstall", value: %{id: plugin.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end

  defp load_page(socket) do
    workspace = socket.assigns.workspace
    opts = list_opts(socket.assigns)
    page = Plugins.list_plugins_paginated(workspace.id, opts)
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

  defp status_badge_class(:enabled), do: "badge-success"
  defp status_badge_class(:disabled), do: "badge-warning"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-info"
end
