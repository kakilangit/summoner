defmodule SummonerWeb.SwarmLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper
  import SummonerWeb.SwarmLive.Helpers

  alias Summoner.Ports.Persistence.Swarms

  @sort_options [{"Name", :name}, {"Mode", :mode}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name, :description]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Partys - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Partys", nil}
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
    authorize(socket, :configure, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      swarm = Swarms.get_swarm!(scope, workspace.id, id)

      case Swarms.delete_swarm(scope, swarm) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Party disbanded.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not disband party.")}
      end
    end)
  end

  defp load_page(socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns
    opts = list_opts(socket.assigns)
    page = Swarms.list_swarms_paginated(scope, workspace.id, opts)
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
        <h1 class="text-2xl font-bold">Partys</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms/new"}
          class="btn btn-primary btn-sm"
        >
          New Party
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search partys..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No partys yet. Form one to group summons together.</p>
        <p :if={@filter != ""}>No partys match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={swarm <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div>
            <div class="flex items-center gap-2">
              <span class="font-medium">
                <.link
                  navigate={
                    ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms/#{swarm.id}"
                  }
                  class="link link-hover"
                >
                  {swarm.name}
                </.link>
              </span>
              <span class={mode_badge_class(swarm.mode)} title={mode_description(swarm.mode)}>
                <span class={mode_icon(swarm.mode)}></span>
                {mode_label(swarm.mode)}
              </span>
            </div>
            <div class="text-sm text-base-content/60">
              {length(swarm.members)} member(s)
            </div>
            <div :if={swarm.description} class="text-sm text-base-content/60">
              {swarm.description}
            </div>
          </div>
          <div class="flex gap-2">
            <.link
              :if={length(swarm.members) > 0}
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms/#{swarm.id}/conversations"
              }
              class="btn btn-primary btn-sm"
            >
              Channels
            </.link>
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms/#{swarm.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-swarm-#{swarm.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Disband
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-swarm-#{swarm.id}"}
              title="Disband party?"
              message="This party and all its member bindings will be permanently removed."
              confirm_text="Disband"
              on_confirm={JS.push("delete", value: %{id: swarm.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end
end
