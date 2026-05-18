defmodule SummonerWeb.SwarmLive.Session do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Broadcasts
  alias Summoner.Conversations
  alias Summoner.Conversations.Content
  alias Summoner.Orchestration
  alias Summoner.Swarms
  alias Summoner.Swarms.SwarmRunner

  alias SummonerWeb.ConversationComponents, as: SC
  alias SummonerWeb.ConversationHelpers, as: SH

  require Logger

  @impl true
  def mount(%{"id" => swarm_id, "conversation_id" => conversation_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope

    swarm = Swarms.get_swarm!(scope, workspace.id, swarm_id)
    conversation = Conversations.get_conversation!(scope, workspace.id, conversation_id)
    messages = Conversations.list_messages(conversation.id, visibility: :public)

    if connected?(socket) do
      Broadcasts.subscribe(Broadcasts.swarm_topic(workspace.id, swarm.id))
      Broadcasts.subscribe(Broadcasts.escalations_topic(workspace.id))
    end

    agent_colors = build_agent_colors(swarm.members)

    socket =
      socket
      |> assign(page_title: "#{swarm.name} Channel - #{workspace.name}")
      |> assign(SH.base_assigns(conversation, messages))
      |> assign(processing: Orchestration.conversation_active?(conversation_id))
      |> assign(
        swarm: swarm,
        current_agent_id: nil,
        current_agent_name: nil,
        turn_count: 0,
        agent_colors: agent_colors
      )
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/realms/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Partys", ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/parties"},
          {swarm.name,
           ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/parties/#{swarm.id}"},
          {"Channels",
           ~p"/realms/#{workspace.tenant_id}/realms/#{workspace.id}/parties/#{swarm.id}/channels"},
          {conversation.title || "Channel", nil}
        ]
      )

    {:ok, socket, layout: {SummonerWeb.Layouts, :chat}}
  end

  # -------------------------------------------------------------------
  # Title editing (delegated)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("edit_title", _params, socket), do: SH.handle_edit_title(socket)

  @impl true
  def handle_event("cancel_edit_title", _params, socket), do: SH.handle_cancel_edit_title(socket)

  @impl true
  def handle_event("save_title", params, socket) do
    default_title = "#{socket.assigns.swarm.name} Channel"
    SH.handle_save_title(params, socket, default_title)
  end

  # -------------------------------------------------------------------
  # Send message — swarm turn routing
  # -------------------------------------------------------------------

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    authorize(socket, :operate, fn ->
      workspace = socket.assigns.workspace
      scope = socket.assigns.current_scope
      conversation = socket.assigns.conversation
      swarm = socket.assigns.swarm

      {_user_msg, messages} =
        SH.write_user_message(conversation, socket.assigns.messages, message)

      subscribe_to_members(workspace.id, swarm)
      SwarmRunner.run_async(swarm, conversation, message, scope)

      {:noreply,
       assign(
         socket,
         SH.processing_assigns(messages) ++
           [turn_count: 0, current_agent_id: nil, current_agent_name: "Coordinator"]
       )}
    end)
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  # -------------------------------------------------------------------
  # Message actions (delegated)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("cancel_invocation", _p, socket) do
    {:noreply, result_socket} = SH.handle_cancel_invocation(socket)

    {:noreply,
     assign(result_socket,
       current_agent_id: nil,
       current_agent_name: nil
     )}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_media_mode", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("dismiss_escalation", _p, socket), do: SH.handle_dismiss_escalation(socket)

  @impl true
  def handle_event("delete_message", params, socket), do: SH.handle_delete_message(params, socket)

  @impl true
  def handle_event("restore_message", params, socket),
    do: SH.handle_restore_message(params, socket)

  @impl true
  def handle_event("edit_message", params, socket), do: SH.handle_edit_message(params, socket)

  @impl true
  def handle_event("cancel_edit", _params, socket), do: SH.handle_cancel_edit(socket)

  @impl true
  def handle_event("save_edit", %{"content" => content}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      conversation = socket.assigns.conversation
      swarm = socket.assigns.swarm
      scope = socket.assigns.current_scope

      messages =
        SH.prepare_reinvoke(conversation, socket.assigns.editing_message_id, content)

      subscribe_to_members(socket.assigns.workspace.id, swarm)
      SwarmRunner.run_async(swarm, conversation, content, scope)

      {:noreply,
       assign(
         socket,
         SH.processing_assigns(messages) ++
           [turn_count: 0, current_agent_id: nil, current_agent_name: "Coordinator"]
       )}
    end
  end

  @impl true
  def handle_event("resend_message", %{"id" => id}, socket) do
    conversation = socket.assigns.conversation
    swarm = socket.assigns.swarm
    scope = socket.assigns.current_scope

    {message, messages} = SH.prepare_resend(conversation, id)
    subscribe_to_members(socket.assigns.workspace.id, swarm)

    SwarmRunner.run_async(
      swarm,
      conversation,
      Content.text_only(message.content),
      scope
    )

    {:noreply,
     assign(
       socket,
       SH.processing_assigns(messages) ++
         [turn_count: 0, current_agent_id: nil, current_agent_name: "Coordinator"]
     )}
  end

  @impl true
  def handle_event("download", _params, socket) do
    title = socket.assigns.conversation.title || "#{socket.assigns.swarm.name} Channel"
    SH.handle_download(socket, title)
  end

  @impl true
  def handle_event("open_workspace", _params, socket) do
    workspace = socket.assigns.workspace

    case Summoner.Workspaces.open_workspace_dir(workspace.id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not open folder: #{reason}")}
    end
  end

  @impl true
  def handle_event("dismiss_error", _params, socket), do: SH.handle_dismiss_error(socket)

  @impl true
  def handle_event("retry_media_generation", %{"id" => attachment_id}, socket) do
    SummonerWeb.MediaRetry.handle_retry(attachment_id, socket)
  end

  # -------------------------------------------------------------------
  # PubSub: Party-specific events
  # -------------------------------------------------------------------

  @impl true
  def handle_info({:swarm_turn, conversation_id, agent_id}, socket) do
    if conversation_id == socket.assigns.conversation.id do
      agent_name = agent_name_for(socket.assigns.swarm, agent_id)

      {:noreply,
       assign(socket,
         current_agent_id: agent_id,
         current_agent_name: agent_name,
         turn_count: socket.assigns.turn_count + 1,
         streaming_content: ""
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:swarm_done, conversation_id, _summary}, socket) do
    if conversation_id == socket.assigns.conversation.id do
      messages =
        Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

      unsubscribe_from_members(socket.assigns.workspace.id, socket.assigns.swarm)

      {:noreply,
       assign(socket,
         messages: messages,
         processing: false,
         current_agent_id: nil,
         current_agent_name: nil,
         streaming_content: "",
         invocation_events: [],
         current_invocation_id: nil,
         subtasks: []
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:swarm_timeout, conversation_id, agent_id}, socket) do
    if conversation_id == socket.assigns.conversation.id do
      agent_name = agent_name_for(socket.assigns.swarm, agent_id)
      Logger.warning("Agent #{agent_name} timed out in swarm session")

      {:noreply,
       socket
       |> assign(streaming_content: "")
       |> put_flash(:error, "#{agent_name} timed out. The party will skip to the next member.")}
    else
      {:noreply, socket}
    end
  end

  # -------------------------------------------------------------------
  # PubSub: Agent events (delegated)
  # -------------------------------------------------------------------

  @impl true
  def handle_info({:content_token, _, _} = msg, socket),
    do: SH.handle_content_token(msg, socket)

  @impl true
  def handle_info({:invocation_status, _, :running} = msg, socket),
    do: SH.handle_invocation_running(msg, socket)

  @impl true
  def handle_info({:invocation_status, _, :completed}, socket) do
    messages =
      Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

    {:noreply, assign(socket, messages: messages, streaming_content: "")}
  end

  @impl true
  def handle_info({:invocation_status, _, :failed, output}, socket) do
    {:noreply, result_socket} = SH.handle_invocation_failed(socket, output)

    {:noreply,
     assign(result_socket,
       current_agent_id: nil,
       current_agent_name: nil
     )}
  end

  @impl true
  def handle_info({:invocation_status, _, :failed}, socket) do
    {:noreply, result_socket} = SH.handle_invocation_failed(socket, nil)

    {:noreply,
     assign(result_socket,
       current_agent_id: nil,
       current_agent_name: nil
     )}
  end

  @impl true
  def handle_info({:invocation_event, _} = msg, socket),
    do: SH.handle_invocation_event(msg, socket)

  @impl true
  def handle_info({:escalation, _, _} = msg, socket),
    do: SH.handle_escalation(msg, socket)

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="flex flex-col h-full mx-auto max-w-7xl w-full px-4 sm:px-6 lg:px-8 overflow-hidden"
      id="session-container"
      phx-hook="DownloadFile"
    >
      <%!-- Header --%>
      <div class="flex-shrink-0 py-2 border-b border-base-300">
        <div class="flex items-center justify-between">
          <SC.title_editor
            conversation={@conversation}
            editing_title={@editing_title}
            default_title={"#{@swarm.name} Channel"}
          >
            <:extra_badges>
              <span class={mode_badge_class(@swarm.mode)}>
                <span class={mode_icon(@swarm.mode)}></span>
                {mode_label(@swarm.mode)}
              </span>
            </:extra_badges>
          </SC.title_editor>
          <div class="flex items-center gap-1">
            <.link
              navigate={~p"/realms/#{@workspace.tenant_id}/realms/#{@workspace.id}/scrolls"}
              class="btn btn-ghost btn-xs gap-1"
              title="Browse workspace files"
            >
              <span class="hero-folder size-4"></span>
              <span class="hidden sm:inline">Browse</span>
            </.link>
            <button
              :if={@local_mode}
              phx-click="open_workspace"
              class="btn btn-ghost btn-xs gap-1"
              title="Open workspace folder"
            >
              <span class="hero-folder-open size-4"></span>
              <span class="hidden sm:inline">Open</span>
            </button>
            <button
              :if={@messages != []}
              phx-click="download"
              class="btn btn-ghost btn-xs gap-1"
              title="Download transcript"
            >
              <span class="hero-arrow-down-tray size-4"></span>
              <span class="hidden sm:inline">Download</span>
            </button>
          </div>
        </div>
        <div class="flex items-center gap-2 mt-1 flex-wrap">
          <div :for={member <- @swarm.members} class="flex items-center gap-1">
            <div class={[
              "size-3 rounded-full",
              agent_color_class(@agent_colors, member.agent_id)
            ]}>
            </div>
            <span class="text-xs text-base-content/60">{member.agent.name}</span>
            <span
              :if={@current_agent_id == member.agent_id}
              class="loading loading-dots loading-xs text-primary"
            >
            </span>
          </div>
          <span :if={@processing} class="text-xs text-base-content/40 ml-2">
            Turn {@turn_count}/{@swarm.max_turns}
          </span>
        </div>
      </div>

      <SC.escalation_alert escalation={@escalation} />

      <%!-- Messages --%>
      <div class="flex-1 overflow-y-auto py-4 space-y-3" id="messages" phx-hook="ScrollBottom">
        <div :if={@messages == []} class="flex flex-col items-center justify-center h-full gap-3">
          <div class="text-base-content/15">
            <span class="hero-chat-bubble-left-right size-16 inline-block"></span>
          </div>
          <p class="text-base-content/40 text-sm">
            Begin the party channel by sending a message below.
          </p>
        </div>

        <SC.message_row
          :for={msg <- @messages}
          msg={msg}
          editing_message_id={@editing_message_id}
          editing_message_content={@editing_message_content}
        >
          <:avatar_assistant>
            <div class={[
              "size-8 rounded-full flex items-center justify-center",
              agent_avatar_class(@agent_colors, msg.agent_id)
            ]}>
              <span class="hero-sparkles size-4"></span>
            </div>
          </:avatar_assistant>
          <:agent_label>
            <div class={[
              "text-xs font-medium mb-1",
              agent_name_class(@agent_colors, msg.agent_id)
            ]}>
              {agent_name_for(@swarm, msg.agent_id)}
            </div>
          </:agent_label>
        </SC.message_row>

        <SC.inline_error last_error={@last_error} />

        <%!-- Streaming content --%>
        <div :if={@streaming_content != ""} class="flex items-start gap-2 justify-start">
          <div class="flex-shrink-0">
            <div class={[
              "size-8 rounded-full flex items-center justify-center",
              agent_avatar_class(@agent_colors, @current_agent_id)
            ]}>
              <span class="hero-sparkles size-4 animate-pulse"></span>
            </div>
          </div>
          <div class="max-w-prose rounded-2xl rounded-tl-sm px-3 py-1.5 bg-base-200 border border-base-300">
            <div class={[
              "text-xs font-medium mb-1",
              agent_name_class(@agent_colors, @current_agent_id)
            ]}>
              {agent_name_for(@swarm, @current_agent_id)}
            </div>
            <div class="prose prose-sm max-w-none break-words chat-prose whitespace-pre-wrap">
              {@streaming_content}<span class="animate-pulse text-primary">|</span>
            </div>
          </div>
        </div>

        <%!-- Processing indicator --%>
        <div
          :if={@processing && @streaming_content == ""}
          class="flex items-start gap-2 justify-start"
        >
          <div class="flex-shrink-0">
            <div class={[
              "size-8 rounded-full flex items-center justify-center",
              agent_avatar_class(@agent_colors, @current_agent_id)
            ]}>
              <span class="hero-sparkles size-4 animate-pulse"></span>
            </div>
          </div>
          <div class="rounded-2xl rounded-tl-sm px-3 py-2 bg-base-200 border border-base-300">
            <div :if={@current_agent_name} class="text-xs font-medium mb-1 text-base-content/60">
              {if @current_agent_id,
                do: "#{@current_agent_name} is thinking...",
                else: "#{@current_agent_name} is routing..."}
            </div>
            <span class="loading loading-dots loading-sm text-primary"></span>
          </div>
        </div>
      </div>

      <SC.subtask_panel subtasks={@subtasks} />
      <SC.thought_stream invocation_events={@invocation_events} />
      <SC.message_input
        message_input={@message_input}
        processing={@processing}
        placeholder="Message the party..."
      />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp subscribe_to_members(workspace_id, swarm) do
    for member <- swarm.members do
      topic = Broadcasts.agent_topic(workspace_id, member.agent_id)
      Broadcasts.subscribe(topic)
    end
  end

  defp unsubscribe_from_members(workspace_id, swarm) do
    for member <- swarm.members do
      topic = Broadcasts.agent_topic(workspace_id, member.agent_id)
      Broadcasts.unsubscribe(topic)
    end
  end

  defp build_agent_colors(members) do
    colors = ~w(primary secondary accent info success warning error)

    members
    |> Enum.with_index()
    |> Map.new(fn {member, idx} ->
      {member.agent_id, Enum.at(colors, rem(idx, length(colors)))}
    end)
  end

  defp agent_color_class(colors, agent_id) do
    color = Map.get(colors, agent_id, "primary")
    "bg-#{color}"
  end

  defp agent_avatar_class(colors, agent_id) do
    color = Map.get(colors, agent_id, "primary")
    "bg-#{color}/10 text-#{color}"
  end

  defp agent_name_class(colors, agent_id) do
    color = Map.get(colors, agent_id, "primary")
    "text-#{color}"
  end

  defp agent_name_for(swarm, agent_id) do
    case Enum.find(swarm.members, &(&1.agent_id == agent_id)) do
      nil -> "Summon"
      member -> member.agent.name
    end
  end

  defp mode_label(:round_robin), do: "Round Robin"
  defp mode_label(:relay), do: "Relay"
  defp mode_label(:directed), do: "Directed"
  defp mode_label(mode), do: mode

  defp mode_badge_class(:round_robin),
    do: "badge badge-sm gap-1 bg-info/10 text-info border-info/30"

  defp mode_badge_class(:relay),
    do: "badge badge-sm gap-1 bg-warning/10 text-warning border-warning/30"

  defp mode_badge_class(:directed),
    do: "badge badge-sm gap-1 bg-secondary/10 text-secondary border-secondary/30"

  defp mode_badge_class(_), do: "badge badge-sm badge-outline gap-1"

  defp mode_icon(:round_robin), do: "hero-arrow-path-rounded-square size-3"
  defp mode_icon(:relay), do: "hero-link size-3"
  defp mode_icon(:directed), do: "hero-bolt size-3"
  defp mode_icon(_), do: ""
end
