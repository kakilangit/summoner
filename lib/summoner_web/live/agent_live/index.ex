defmodule SummonerWeb.AgentLive.Index do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Agents
  alias Summoner.Agents.Agent

  @sort_options [{"Name", :name}, {"Role", :role}, {"Created", :inserted_at}]
  @default_sort_by :name
  @default_sort_dir :asc
  @filter_fields [:name]

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    socket =
      socket
      |> assign(
        page_title: "Summons - #{workspace.name}",
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Summons", nil}
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
      agent = Agents.get_agent!(scope, workspace.id, id)

      case Agents.delete_agent(scope, agent) do
        {:ok, _} ->
          {:noreply, socket |> load_page() |> put_flash(:info, "Summon deleted.")}

        {:error, changeset} ->
          message = changeset_delete_error(changeset)
          {:noreply, put_flash(socket, :error, message)}
      end
    end)
  end

  defp load_page(socket) do
    %{current_scope: scope, workspace: workspace} = socket.assigns

    opts =
      list_opts(socket.assigns)

    page = Agents.list_agents_paginated(scope, workspace.id, opts)
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

  defp changeset_delete_error(%Ecto.Changeset{errors: errors}) do
    case errors do
      [{_field, {message, _}} | _] -> "Cannot delete summon: #{message}."
      _ -> "Could not delete summon."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Summons</h1>
        <.link
          :if={@can?.(:configure)}
          navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/new"}
          class="btn btn-primary btn-sm"
        >
          New Summon
        </.link>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search summons..."
      />

      <div :if={@page.entries == []} class="text-center py-12 text-base-content/60">
        <p :if={@filter == ""}>No summons yet. Summon one to get started.</p>
        <p :if={@filter != ""}>No summons match your search.</p>
      </div>

      <div class="space-y-2">
        <div
          :for={agent <- @page.entries}
          class="flex items-center justify-between p-4 bg-base-200 rounded-lg"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.link
                navigate={
                  ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{agent.id}"
                }
                class="font-medium hover:underline truncate"
              >
                {agent.name}
              </.link>
              <span
                class={[
                  "badge badge-sm",
                  agent.role == :worker && "badge-info",
                  agent.role == :autonomous && "badge-success"
                ]}
                title={Agent.role_description(agent.role)}
              >
                {agent.role}
              </span>
            </div>
            <div class="text-sm text-base-content/60 truncate">
              {agent.local_agent && agent.local_agent.model}
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <.link
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{agent.id}/runes"
              }
              class="btn btn-ghost btn-sm"
            >
              Runes
            </.link>
            <.link
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{agent.id}/skills"
              }
              class="btn btn-ghost btn-sm"
            >
              Spellbook
            </.link>
            <.link
              :if={@can?.(:configure)}
              navigate={
                ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/summons/#{agent.id}/edit"
              }
              class="btn btn-ghost btn-sm"
            >
              Edit
            </.link>
            <button
              :if={@can?.(:configure)}
              phx-click={show_confirm("#delete-agent-#{agent.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Delete
            </button>
            <.confirm_modal
              :if={@can?.(:configure)}
              id={"delete-agent-#{agent.id}"}
              title="Delete summon?"
              message="This summon and its configuration will be permanently removed. Equipped runes and spells will be unlinked."
              confirm_text="Delete"
              on_confirm={JS.push("delete", value: %{id: agent.id})}
            />
          </div>
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end
end
