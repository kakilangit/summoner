defmodule SummonerWeb.ArtifactLive.Index do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Artifacts

  @sort_options [{"Name", :name}, {"Updated", :updated_at}, {"Type", :type}]
  @default_sort_by :updated_at
  @default_sort_dir :desc
  @filter_fields [:name, :type]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Relics - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Relics", nil}
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
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    artifact = Artifacts.get_artifact!(scope, workspace.id, id)

    case Artifacts.delete_artifact(scope, artifact) do
      {:ok, _} ->
        {:noreply, socket |> load_page() |> put_flash(:info, "Relic removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove relic.")}
    end
  end

  @impl true
  def handle_event("toggle_pin", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    artifact = Artifacts.get_artifact!(scope, workspace.id, id)

    case Artifacts.update_artifact(scope, artifact, %{pinned: !artifact.pinned}) do
      {:ok, _} -> {:noreply, load_page(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update relic.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Relics</h1>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search relics..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>
          No relics yet. Summons create relics when they produce documents, code, or reports.
        </p>
        <p :if={@filter != ""}>No relics match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={artifact <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/artifacts/#{artifact.id}"
                }
                class="font-medium hover:underline"
              >
                {artifact.name}
              </.link>
              <span class="badge badge-ghost badge-xs">{artifact.type}</span>
              <span class="badge badge-ghost badge-xs">v{artifact.version}</span>
              <span :if={artifact.pinned} class="badge badge-warning badge-xs">pinned</span>
            </div>
            <div class="text-sm text-base-content/60 flex items-center gap-2">
              <.link
                :if={artifact.agent}
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/agents/#{artifact.agent_id}"
                }
                class="hover:underline"
              >
                {artifact.agent.name}
              </.link>
              <.link
                :if={artifact.conversation && artifact.conversation.swarm}
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/swarms/#{artifact.conversation.swarm.id}/conversations/#{artifact.conversation_id}"
                }
                class="hover:underline"
              >
                · {artifact.conversation.swarm.name}
              </.link>
              <.link
                :if={artifact.conversation && is_nil(artifact.conversation.swarm)}
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/conversations/#{artifact.conversation_id}"
                }
                class="hover:underline"
              >
                · Channel
              </.link>
              <span>
                · {artifact.content_type} · {Calendar.strftime(
                  artifact.updated_at,
                  "%Y-%m-%d %H:%M"
                )}
              </span>
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <button
              phx-click="toggle_pin"
              phx-value-id={artifact.id}
              class="btn btn-ghost btn-sm"
            >
              {if artifact.pinned, do: "Unpin", else: "Pin"}
            </button>
            <.link
              href={
                ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/artifacts/#{artifact.id}/download"
              }
              class="btn btn-ghost btn-sm"
            >
              Export
            </.link>
            <button
              phx-click={show_confirm("#delete-artifact-#{artifact.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              id={"delete-artifact-#{artifact.id}"}
              title="Delete relic?"
              message="This will soft-delete the relic. It can be recovered later."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: artifact.id})}
            />
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
    page = Artifacts.list_artifacts_paginated(scope, workspace.id, opts)
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
