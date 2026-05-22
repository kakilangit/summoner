defmodule SummonerWeb.KnowledgeBaseLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Ports.Persistence.KnowledgeBases

  @sort_options [
    {"Name", :name},
    {"Type", :type},
    {"Status", :status},
    {"Documents", :document_count},
    {"Created", :inserted_at}
  ]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Codex - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/tenants/#{workspace.tenant_id}/workspaces"},
          {workspace.name, ~p"/tenants/#{workspace.tenant_id}/workspaces/#{workspace.id}"},
          {"Codex", nil}
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
      workspace = socket.assigns.workspace
      kb = KnowledgeBases.get_knowledge_base!(workspace.id, id)

      case KnowledgeBases.delete_knowledge_base(kb) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Codex deleted.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Codex</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={
            ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/knowledge-bases/new"
          }
          class="btn btn-primary btn-sm"
        >
          New Codex
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search knowledge bases..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No knowledge bases yet. Create one to get started.</p>
        <p :if={@filter != ""}>No knowledge bases match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={kb <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/tenants/#{@workspace.tenant_id}/workspaces/#{@workspace.id}/knowledge-bases/#{kb.id}"
                }
                class="font-medium hover:underline"
              >
                {kb.name}
              </.link>
              <span class={["badge badge-sm", status_badge_class(kb.status)]}>
                {kb.status}
              </span>
              <span class="badge badge-sm badge-ghost">{kb.type}</span>
            </div>
            <div class="text-sm text-base-content/60 mt-1">
              {kb.document_count} documents <span class="mx-1">&middot;</span>
              updated {Calendar.strftime(kb.updated_at, "%b %d, %Y")}
            </div>
          </div>
          <div :if={@can?.(:configure)} class="flex gap-2 flex-shrink-0">
            <button
              phx-click={show_confirm("#delete-#{kb.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              id={"delete-#{kb.id}"}
              title="Delete codex?"
              message={"#{kb.name} and all its documents will be permanently removed."}
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: kb.id})}
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
    page = KnowledgeBases.list_knowledge_bases_paginated(workspace.id, opts)
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

  defp status_badge_class(:ready), do: "badge-success"
  defp status_badge_class(:indexing), do: "badge-info"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-warning"
end
