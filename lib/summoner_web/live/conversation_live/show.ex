defmodule SummonerWeb.ConversationLive.Show do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Media
  alias Summoner.Ports.Persistence.MediaProviders
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Ports.Persistence.Workspaces
  alias Summoner.Ports.Workers

  alias Summoner.Domain.Events.{
    ContentToken,
    Escalation,
    InvocationCompleted,
    InvocationEvent,
    InvocationFailed,
    InvocationStarted,
    MediaGenerationCompleted,
    MediaGenerationFailed,
    MediaGenerationStarted
  }

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Types.Content
  alias Summoner.Ports.Events

  alias SummonerWeb.ConversationComponents, as: SC
  alias SummonerWeb.ConversationHelpers, as: SH

  @impl true
  def mount(%{"conversation_id" => conversation_id}, _session, socket) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope

    conversation = Conversations.get_conversation!(scope, workspace.id, conversation_id)
    messages = Conversations.list_messages(conversation_id, visibility: :public)

    if connected?(socket) do
      Events.subscribe({:escalations, workspace.id})
      Events.subscribe({:conversation, workspace.id, conversation_id})

      if conversation.primary_agent_id do
        Events.subscribe({:agent, workspace.id, conversation.primary_agent_id})
      end
    end

    socket =
      socket
      |> assign(page_title: (conversation.title || "Channel") <> " - #{workspace.name}")
      |> assign(SH.base_assigns(conversation, messages))
      |> assign(processing: Orchestration.conversation_active?(conversation_id))
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Channels", ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}/channels"},
          {conversation.title || "Channel", nil}
        ]
      )
      |> SH.setup_uploads()

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
  def handle_event("save_title", params, socket),
    do: SH.handle_save_title(params, socket, "Channel")

  # -------------------------------------------------------------------
  # Model switcher (chat-specific)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("change_model", %{"agent_id" => agent_id, "model" => model}, socket) do
    scope = socket.assigns.current_scope
    agent = socket.assigns.conversation.primary_agent

    if agent && agent.id == agent_id do
      case Agents.update_agent(scope, agent, %{model: model}) do
        {:ok, updated_agent} ->
          updated_agent = Agents.preload_agent(updated_agent)
          conversation = %{socket.assigns.conversation | primary_agent: updated_agent}

          {:noreply,
           socket
           |> assign(conversation: conversation)
           |> put_flash(
             :info,
             "Spirit switched to #{SummonerWeb.CoreComponents.short_model_name(model)}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not switch spirit.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Agent mismatch.")}
    end
  end

  # -------------------------------------------------------------------
  # Send message
  # -------------------------------------------------------------------

  @impl true
  def handle_event("toggle_media_mode", _params, socket) do
    next =
      case socket.assigns.media_mode do
        nil -> :image
        :image -> :video
        :video -> nil
      end

    {:noreply, assign(socket, media_mode: next)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    agent = socket.assigns.conversation.primary_agent

    if agent && agent.deleted_at do
      {:noreply, put_flash(socket, :error, "This summon has been deleted.")}
    else
      authorize(socket, :operate, fn ->
        message = String.trim(message)
        dispatch_message(socket, message)
      end)
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, Phoenix.LiveView.cancel_upload(socket, :images, ref)}
  end

  # -------------------------------------------------------------------
  # Message actions (delegated)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("cancel_invocation", _p, socket), do: SH.handle_cancel_invocation(socket)

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
    dispatch_save_edit(socket, content)
  end

  @impl true
  def handle_event("resend_message", %{"id" => id}, socket) do
    conversation = socket.assigns.conversation

    {message, messages} = SH.prepare_resend(conversation, id)
    text = Content.text_only(message.content)

    if message.kind in [:generate_image, :generate_video] do
      media_mode = if message.kind == :generate_image, do: :image, else: :video
      regenerate_media(socket, conversation, messages, text, media_mode, message.id)
    else
      reinvoke_agent(socket, conversation, messages, text)
    end
  end

  @impl true
  def handle_event("download", _params, socket) do
    title = socket.assigns.conversation.title || "Channel"
    SH.handle_download(socket, title)
  end

  @impl true
  def handle_event("open_workspace", _params, socket) do
    workspace = socket.assigns.workspace

    case Workspaces.open_workspace_dir(workspace.id) do
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
  # PubSub handlers (delegated)
  # -------------------------------------------------------------------

  @impl true
  def handle_info(%ContentToken{} = event, socket),
    do: SH.handle_content_token(event, socket)

  @impl true
  def handle_info(%InvocationStarted{} = event, socket),
    do: SH.handle_invocation_running(event, socket)

  @impl true
  def handle_info(%InvocationCompleted{}, socket),
    do: SH.handle_invocation_completed(socket)

  @impl true
  def handle_info(%InvocationFailed{output: output}, socket),
    do: SH.handle_invocation_failed(socket, output)

  @impl true
  def handle_info(%InvocationEvent{} = event, socket),
    do: SH.handle_invocation_event(event, socket)

  @impl true
  def handle_info(%Escalation{} = event, socket),
    do: SH.handle_escalation(event, socket)

  @impl true
  def handle_info(%MediaGenerationCompleted{attachment_id: id}, socket) do
    messages =
      Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

    {:noreply,
     assign(socket,
       messages: messages,
       pending_generations: MapSet.delete(socket.assigns.pending_generations, id)
     )}
  end

  @impl true
  def handle_info(%MediaGenerationFailed{attachment_id: id}, socket) do
    messages =
      Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

    {:noreply,
     assign(socket,
       messages: messages,
       pending_generations: MapSet.delete(socket.assigns.pending_generations, id)
     )}
  end

  @impl true
  def handle_info(%MediaGenerationStarted{}, socket) do
    {:noreply, socket}
  end

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
      id="conversation-container"
      phx-hook="DownloadFile"
    >
      <%!-- Header --%>
      <div class="flex-shrink-0 py-2 border-b border-base-300">
        <div class="flex items-center justify-between">
          <SC.title_editor
            conversation={@conversation}
            editing_title={@editing_title}
            default_title="Channel"
          />
          <div class="flex items-center gap-1">
            <.link
              navigate={~p"/guilds/#{@workspace.tenant_id}/realms/#{@workspace.id}/scrolls"}
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
        <div :if={@conversation.primary_agent} class="flex items-center gap-2 mt-1">
          <.agent_icon agent={@conversation.primary_agent} size={:sm} />
          <span class="text-sm font-medium text-base-content/70">
            {@conversation.primary_agent.name}
          </span>
          <span
            :if={@conversation.primary_agent.deleted_at}
            class="badge badge-xs badge-error"
          >
            deleted
          </span>
          <span
            :if={Agent.description(@conversation.primary_agent)}
            class="text-xs text-base-content/40 truncate max-w-xs"
            title={Agent.description(@conversation.primary_agent)}
          >
            — {Agent.description(@conversation.primary_agent)}
          </span>
          <.model_switcher agent={@conversation.primary_agent} id="chat-model-switcher" />
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
            Begin the channel by sending a message below.
          </p>
        </div>

        <SC.message_row
          :for={msg <- @messages}
          msg={msg}
          editing_message_id={@editing_message_id}
          editing_message_content={@editing_message_content}
        >
          <:avatar_assistant>
            <.agent_icon agent={@conversation.primary_agent} size={:md} />
          </:avatar_assistant>
          <:agent_label>
            <div class={[
              "text-xs font-medium mb-1",
              if(@conversation.primary_agent.type == :remote,
                do: "text-secondary/70",
                else: "text-primary/70"
              )
            ]}>
              {if @conversation.primary_agent.type == :remote, do: "Envoy", else: "Summon"}
            </div>
          </:agent_label>
        </SC.message_row>

        <SC.inline_error last_error={@last_error} />

        <%!-- Artifact channeling indicator --%>
        <div
          :if={MapSet.size(@pending_generations) > 0}
          class="flex items-start gap-2 justify-start"
        >
          <div class="flex-shrink-0">
            <div class="size-8 rounded-full bg-accent/10 flex items-center justify-center">
              <span class="hero-sparkles size-4 text-accent animate-pulse"></span>
            </div>
          </div>
          <div class="rounded-2xl rounded-tl-sm px-3 py-2 bg-base-200 border border-accent/30">
            <div class="flex items-center gap-2 text-sm text-accent">
              <span class="loading loading-ring loading-sm"></span>
              <span>Standing By...</span>
            </div>
          </div>
        </div>

        <%!-- Streaming content --%>
        <div :if={@streaming_content != ""} class="flex items-start gap-2 justify-start">
          <div class="flex-shrink-0">
            <.agent_icon agent={@conversation.primary_agent} size={:md} animate />
          </div>
          <div class="max-w-prose rounded-2xl rounded-tl-sm px-3 py-1.5 bg-base-200 border border-base-300">
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
            <.agent_icon agent={@conversation.primary_agent} size={:md} animate />
          </div>
          <div class="rounded-2xl rounded-tl-sm px-3 py-2 bg-base-200 border border-base-300">
            <span class="loading loading-dots loading-sm text-primary"></span>
          </div>
        </div>
      </div>

      <SC.subtask_panel subtasks={@subtasks} />
      <SC.thought_stream invocation_events={@invocation_events} />
      <div
        :if={@conversation.primary_agent && @conversation.primary_agent.deleted_at}
        class="px-4 py-3 bg-error/10 border-t border-error/20 text-sm text-error"
      >
        This summon has been deleted. Chat is disabled.
      </div>
      <SC.message_input
        :if={!@conversation.primary_agent || !@conversation.primary_agent.deleted_at}
        message_input={@message_input}
        processing={@processing}
        placeholder="Message..."
        uploads={@uploads}
        media_mode={@media_mode}
      />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp dispatch_message(socket, ""), do: {:noreply, socket}

  defp dispatch_message(socket, message) do
    if socket.assigns.media_mode do
      handle_media_message(socket, message)
    else
      handle_chat_message(socket, message)
    end
  end

  defp dispatch_save_edit(socket, ""), do: {:noreply, socket}

  defp dispatch_save_edit(socket, content) do
    conversation = socket.assigns.conversation
    editing_id = socket.assigns.editing_message_id
    original_msg = Conversations.get_message!(editing_id)

    messages = SH.prepare_reinvoke(conversation, editing_id, content)

    if original_msg.kind in [:generate_image, :generate_video] do
      media_mode = if original_msg.kind == :generate_image, do: :image, else: :video
      regenerate_media(socket, conversation, messages, content, media_mode, editing_id)
    else
      reinvoke_agent(socket, conversation, messages, content)
    end
  end

  defp reinvoke_agent(socket, conversation, messages, content) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope

    if conversation.primary_agent do
      Agents.execute_async(conversation.primary_agent, workspace.id, %{
        conversation_id: conversation.id,
        message: content,
        scope: scope
      })
    end

    {:noreply, assign(socket, SH.processing_assigns(messages))}
  end

  defp handle_chat_message(socket, message) do
    workspace = socket.assigns.workspace
    scope = socket.assigns.current_scope
    conversation = socket.assigns.conversation

    {user_msg, messages} =
      SH.write_user_message_with_uploads(
        socket,
        conversation,
        socket.assigns.messages,
        message
      )

    if user_msg && conversation.primary_agent do
      text = Content.text_only(user_msg.content)

      Agents.execute_async(conversation.primary_agent, workspace.id, %{
        conversation_id: conversation.id,
        message: text,
        scope: scope
      })
    end

    {:noreply, assign(socket, SH.processing_assigns(messages))}
  end

  # Regenerate media for an existing message (resend/edit) — no new message created.
  defp regenerate_media(socket, conversation, messages, prompt, media_mode, message_id) do
    agent = conversation.primary_agent

    case MediaProviders.resolve_media_provider(agent, media_mode) do
      nil ->
        label = if media_mode == :image, do: "image", else: "video"

        {:noreply,
         socket
         |> assign(messages: messages)
         |> put_flash(:error, "No forge configured for #{label} generation.")}

      media_provider ->
        attachment =
          enqueue_media_generation(socket, conversation, media_provider, prompt, media_mode,
            message_id: message_id
          )

        {:noreply,
         assign(socket,
           messages: messages,
           pending_generations: MapSet.put(socket.assigns.pending_generations, attachment.id)
         )}
    end
  end

  defp handle_media_message(socket, prompt) do
    conversation = socket.assigns.conversation
    media_mode = socket.assigns.media_mode
    agent = conversation.primary_agent

    case MediaProviders.resolve_media_provider(agent, media_mode) do
      nil ->
        label = if media_mode == :image, do: "image", else: "video"

        {:noreply, put_flash(socket, :error, "No forge configured for #{label} generation.")}

      media_provider ->
        media_kind = if media_mode == :image, do: :generate_image, else: :generate_video

        {user_msg, messages} =
          SH.write_user_message(conversation, socket.assigns.messages, prompt, kind: media_kind)

        attachment =
          enqueue_media_generation(socket, conversation, media_provider, prompt, media_mode,
            message_id: user_msg.id
          )

        {:noreply,
         assign(socket,
           messages: messages,
           message_input: "",
           pending_generations: MapSet.put(socket.assigns.pending_generations, attachment.id)
         )}
    end
  end

  defp enqueue_media_generation(socket, conversation, media_provider, prompt, media_mode, opts) do
    workspace = socket.assigns.workspace
    message_id = Keyword.get(opts, :message_id)
    {ext, content_type, default_model} = media_type_config(media_mode, media_provider)

    {:ok, attachment} =
      Media.create_pending_attachment(%{
        workspace_id: workspace.id,
        conversation_id: conversation.id,
        message_id: message_id,
        source: :generated,
        type: media_mode,
        filename: "generated_#{System.unique_integer([:positive])}.#{ext}",
        content_type: content_type,
        prompt: prompt,
        model_name: default_model,
        provider_name: media_provider.name,
        metadata: %{}
      })

    Workers.enqueue_media_generation(%{
      "attachment_id" => attachment.id,
      "media_provider_id" => media_provider.id,
      "message_id" => message_id,
      "type" => to_string(media_mode),
      "params" => %{"prompt" => prompt}
    })

    attachment
  end

  defp media_type_config(:image, media_provider) do
    {"png", "image/png", media_provider.default_image_model || "gpt-image-1"}
  end

  defp media_type_config(:video, media_provider) do
    {"mp4", "video/mp4", media_provider.default_video_model || "sora"}
  end
end
