defmodule SummonerWeb.SwarmLive.Conversations do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Adapters.Persistence.Conversations
  alias Summoner.Adapters.Persistence.Swarms

  @sort_options [{"Title", :title}, {"Created", :inserted_at}]
  @default_sort_by :inserted_at
  @default_sort_dir :desc
  @filter_fields [:title]

  @impl true
  def mount(%{"id" => swarm_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    swarm = Swarms.get_swarm!(scope, workspace.id, swarm_id)

    socket =
      socket
      |> assign(
        page_title: "#{swarm.name} Channels - #{workspace.name}",
        swarm: swarm,
        sort_by: @default_sort_by,
        sort_dir: @default_sort_dir,
        filter: "",
        sort_options: @sort_options
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Partys", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties"},
          {swarm.name,
           ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties/#{swarm.id}"},
          {"Channels", nil}
        ]
      )
      |> load_page()

    {:ok, socket}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    authorize(socket, :operate, fn ->
      scope = socket.assigns.current_scope
      workspace = socket.assigns.workspace
      swarm = socket.assigns.swarm

      case Swarms.create_conversation(scope, swarm) do
        {:ok, conversation} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/parties/#{swarm.id}/channels/#{conversation.id}"
           )}

        {:error, :no_members} ->
          {:noreply, put_flash(socket, :error, "Add members to the party first.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create channel.")}
      end
    end)
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
  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> assign(page_num: String.to_integer(page_num)) |> load_page()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    workspace = socket.assigns.workspace
    conversation = Conversations.get_conversation!(scope, workspace.id, id)

    case Conversations.delete_conversation(scope, conversation) do
      {:ok, _} ->
        {:noreply, socket |> load_page() |> put_flash(:info, "Channel deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete channel.")}
    end
  end

  defp load_page(socket) do
    %{swarm: swarm} = socket.assigns
    opts = list_opts(socket.assigns)
    scope = socket.assigns.current_scope
    page = Swarms.list_swarm_conversations_paginated(scope, swarm.id, opts)
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
        <h1 class="text-2xl font-bold">{@swarm.name} Channels</h1>
        <div class="flex-shrink-0">
          <button
            :if={@can?.(:operate)}
            phx-click="new_conversation"
            class="btn btn-primary btn-sm gap-1"
          >
            <span class="hero-plus size-4"></span> New Channel
          </button>
        </div>
      </div>

      <.list_controls
        filter={@filter}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        sort_options={@sort_options}
        placeholder="Search channels..."
      />

      <%!-- Empty state --%>
      <div :if={@page.entries == []} class="text-center py-16">
        <div class="text-base-content/20 mb-4">
          <span class="hero-chat-bubble-left-right size-16 inline-block"></span>
        </div>
        <p :if={@filter == ""} class="text-base-content/50">
          No channels yet. Begin one to commune with the party.
        </p>
        <p :if={@filter != ""} class="text-base-content/50">No channels match your search.</p>
      </div>

      <%!-- Conversation list --%>
      <div class="space-y-2">
        <div
          :for={conversation <- @page.entries}
          class="group flex items-center gap-4 p-4 bg-base-200/50 border border-base-300 rounded-xl hover:border-primary/30 hover:shadow-sm transition-all"
        >
          <.link
            navigate={
              ~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/parties/#{@swarm.id}/channels/#{conversation.id}"
            }
            class="flex items-center gap-4 min-w-0 flex-1"
          >
            <div class="flex-shrink-0 size-10 rounded-full bg-base-300 flex items-center justify-center text-base-content/40 group-hover:text-primary transition-colors">
              <span class="hero-chat-bubble-left size-5"></span>
            </div>
            <div class="min-w-0 flex-1">
              <div class="font-medium truncate group-hover:text-primary transition-colors">
                {conversation.title || "Untitled"}
              </div>
              <div class="text-xs text-base-content/50 mt-0.5">
                {Summoner.Services.TimeZone.format(conversation.inserted_at,
                  format: "%b %d, %Y at %H:%M"
                )}
              </div>
            </div>
          </.link>
          <div class="flex-shrink-0">
            <button
              phx-click={show_confirm("#delete-conv-#{conversation.id}")}
              class="btn btn-ghost btn-sm btn-square opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <span class="hero-trash size-4 text-error"></span>
            </button>
          </div>
          <.confirm_modal
            id={"delete-conv-#{conversation.id}"}
            title="Delete channel?"
            message="All messages in this channel will be permanently lost."
            confirm_text="Delete"
            on_confirm={JS.push("delete", value: %{id: conversation.id})}
          />
        </div>
      </div>

      <.pagination page={@page} />
    </div>
    """
  end
end
