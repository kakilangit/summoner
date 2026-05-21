defmodule SummonerWeb.ConversationHelpers do
  @moduledoc """
  Shared event-handling logic for channel LiveViews (ConversationLive.Show and SwarmLive.Session).

  Both channel views share identical behaviour for title editing, message actions
  (delete/restore/edit/resend), cancellation, error dismissal, and PubSub
  handlers for invocation lifecycle. This module extracts those into plain
  functions that each LiveView delegates to.

  ## Usage

      # In handle_event:
      def handle_event("delete_message", params, socket) do
        ConversationHelpers.handle_delete_message(params, socket)
      end

      # In handle_info:
      def handle_info(%Events.ContentToken{} = msg, socket) do
        ConversationHelpers.handle_content_token(msg, socket)
      end
  """

  alias Summoner.Domain.Events.{
    ContentToken,
    Escalation,
    Failover,
    InvocationEvent,
    InvocationStarted
  }

  alias Summoner.Domain.Types.Content
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Media
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Services.Orchestration.Cancellation

  import Phoenix.Component, only: [assign: 2]

  import Phoenix.LiveView,
    only: [allow_upload: 3, consume_uploaded_entries: 3, push_event: 3, put_flash: 3]

  @max_upload_entries 4
  @max_upload_size 10_485_760

  @doc """
  Configures the socket for image uploads.
  Call this in mount/3 of the LiveView.
  """
  def setup_uploads(socket) do
    allow_upload(socket, :images,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: @max_upload_entries,
      max_file_size: @max_upload_size
    )
  end

  @doc """
  Processes uploaded images and returns content blocks for them.
  Creates MediaAttachment records and stores files on disk.
  Returns a list of image content blocks.
  """
  def consume_uploads(socket, workspace_id, conversation_id) do
    consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
      binary = File.read!(path)
      content_type = entry.client_type

      {:ok, attachment} =
        Media.create_uploaded_attachment(%{
          workspace_id: workspace_id,
          conversation_id: conversation_id,
          type: :image,
          filename: entry.client_name,
          content_type: content_type,
          file_size: byte_size(binary),
          metadata: %{}
        })

      :ok = Media.store_file(attachment, binary)

      {:ok,
       %{
         "type" => "image",
         "media_attachment_id" => attachment.id,
         "alt" => entry.client_name
       }}
    end)
  end

  @doc """
  Writes a user message with optional image attachments.
  Returns `{user_msg, updated_messages}`.
  """
  def write_user_message_with_uploads(socket, conversation, messages, text_content) do
    workspace_id = conversation.workspace_id
    image_blocks = consume_uploads(socket, workspace_id, conversation.id)

    content_blocks =
      if text_content != "" do
        [%{"type" => "text", "text" => text_content}]
      else
        []
      end

    content_blocks = content_blocks ++ image_blocks

    if content_blocks == [] do
      {nil, messages}
    else
      {:ok, user_msg} =
        Conversations.add_message(%{
          conversation_id: conversation.id,
          role: :user,
          content: content_blocks
        })

      {user_msg, messages ++ [user_msg]}
    end
  end

  # -------------------------------------------------------------------
  # Title editing
  # -------------------------------------------------------------------

  def handle_edit_title(socket) do
    {:noreply, assign(socket, editing_title: true)}
  end

  def handle_cancel_edit_title(socket) do
    {:noreply, assign(socket, editing_title: false)}
  end

  def handle_save_title(%{"title" => title}, socket, default_title) do
    scope = socket.assigns.current_scope
    conversation = socket.assigns.conversation

    case Conversations.update_conversation(scope, conversation, %{title: title}) do
      {:ok, conversation} ->
        {:noreply,
         assign(socket,
           conversation: conversation,
           editing_title: false,
           page_title:
             (conversation.title || default_title) <>
               " - #{socket.assigns.workspace.name}"
         )}

      {:error, _changeset} ->
        {:noreply,
         socket |> assign(editing_title: false) |> put_flash(:error, "Could not rename channel.")}
    end
  end

  # -------------------------------------------------------------------
  # Message actions
  # -------------------------------------------------------------------

  def handle_delete_message(%{"id" => id}, socket) do
    message = Conversations.get_message!(id)
    {:ok, updated} = Conversations.soft_delete_message(message)

    messages =
      Enum.map(socket.assigns.messages, fn m ->
        if m.id == updated.id, do: updated, else: m
      end)

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_restore_message(%{"id" => id}, socket) do
    message = Conversations.get_message!(id)
    {:ok, updated} = Conversations.restore_message(message)

    messages =
      Enum.map(socket.assigns.messages, fn m ->
        if m.id == updated.id, do: updated, else: m
      end)

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_edit_message(%{"id" => id}, socket) do
    message = Conversations.get_message!(id)

    {:noreply,
     assign(socket,
       editing_message_id: id,
       editing_message_content: Content.text_only(message.content)
     )}
  end

  def handle_cancel_edit(socket) do
    {:noreply, assign(socket, editing_message_id: nil, editing_message_content: "")}
  end

  # -------------------------------------------------------------------
  # Cancel / dismiss
  # -------------------------------------------------------------------

  def handle_cancel_invocation(socket) do
    case socket.assigns.current_invocation_id do
      nil ->
        {:noreply, socket}

      invocation_id ->
        case Cancellation.cancel_tree(invocation_id) do
          {:ok, count} ->
            messages =
              Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

            {:noreply,
             socket
             |> assign(
               processing: false,
               streaming_content: "",
               invocation_events: [],
               current_invocation_id: nil,
               subtasks: [],
               messages: messages
             )
             |> put_flash(:info, "Cancelled #{count} invocation(s).")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not cancel.")}
        end
    end
  end

  def handle_dismiss_escalation(socket) do
    {:noreply, assign(socket, escalation: nil)}
  end

  def handle_dismiss_error(socket) do
    {:noreply, assign(socket, last_error: nil)}
  end

  # -------------------------------------------------------------------
  # PubSub: Invocation lifecycle
  # -------------------------------------------------------------------

  def handle_content_token(
        %ContentToken{invocation_id: invocation_id, token: token},
        socket
      ) do
    if invocation_id == socket.assigns[:current_invocation_id] do
      {:noreply, assign(socket, streaming_content: socket.assigns.streaming_content <> token)}
    else
      {:noreply, socket}
    end
  end

  def handle_invocation_running(%InvocationStarted{invocation_id: invocation_id}, socket) do
    workspace = socket.assigns.workspace
    Events.subscribe({:invocation_events, workspace.id, invocation_id})
    {:noreply, assign(socket, current_invocation_id: invocation_id)}
  end

  def handle_invocation_completed(socket) do
    messages =
      Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

    {:noreply,
     assign(socket,
       messages: messages,
       streaming_content: "",
       processing: false,
       invocation_events: [],
       current_invocation_id: nil,
       subtasks: []
     )}
  end

  def handle_invocation_failed(socket, output) do
    messages =
      Conversations.list_messages(socket.assigns.conversation.id, visibility: :public)

    error_detail = extract_error_detail(output)

    {:noreply,
     assign(socket,
       messages: messages,
       streaming_content: "",
       processing: false,
       invocation_events: [],
       current_invocation_id: nil,
       subtasks: [],
       last_error: error_detail
     )}
  end

  def handle_invocation_event(%InvocationEvent{event: event}, socket) do
    events = socket.assigns.invocation_events ++ [event]
    subtasks = refresh_subtasks(socket.assigns.current_invocation_id)
    {:noreply, assign(socket, invocation_events: events, subtasks: subtasks)}
  end

  def handle_escalation(%Escalation{invocation_id: invocation_id, reason: reason}, socket) do
    subtasks = refresh_subtasks(invocation_id)

    {:noreply,
     assign(socket,
       escalation: %{invocation_id: invocation_id, reason: reason},
       subtasks: subtasks
     )}
  end

  def handle_failover(%Failover{} = event, socket) do
    from = Agents.get_agent_name(event.from_agent_id)
    to = Agents.get_agent_name(event.to_agent_id)

    {:noreply,
     assign(socket,
       failover_event: %{
         from: from,
         to: to,
         reason: event.reason,
         depth: event.depth
       }
     )}
  end

  def handle_dismiss_failover(socket) do
    {:noreply, assign(socket, failover_event: nil)}
  end

  # -------------------------------------------------------------------
  # Download / export
  # -------------------------------------------------------------------

  def handle_download(socket, title) do
    conversation = socket.assigns.conversation
    markdown = Conversations.export_as_markdown(conversation.id, title: title)
    slug = slugify(title)
    filename = "#{slug}.md"

    {:noreply,
     push_event(socket, "download_file", %{
       filename: filename,
       content: markdown,
       content_type: "text/markdown"
     })}
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 80)
  end

  # -------------------------------------------------------------------
  # Common assign initialization
  # -------------------------------------------------------------------

  @doc """
  Returns the common assigns shared by both channel views.
  Callers should merge these into their socket alongside view-specific assigns.
  """
  def base_assigns(conversation, messages) do
    [
      conversation: conversation,
      messages: messages,
      message_input: "",
      streaming_content: "",
      invocation_events: [],
      processing: false,
      editing_title: false,
      escalation: nil,
      failover_event: nil,
      current_invocation_id: nil,
      subtasks: [],
      last_error: nil,
      editing_message_id: nil,
      editing_message_content: "",
      media_mode: nil,
      pending_generations: MapSet.new()
    ]
  end

  @doc """
  Assigns to reset after a send/resend/edit-save that triggers a new invocation.
  """
  def processing_assigns(messages) do
    [
      messages: messages,
      message_input: "",
      streaming_content: "",
      processing: true,
      escalation: nil,
      last_error: nil,
      editing_message_id: nil,
      editing_message_content: ""
    ]
  end

  @doc """
  Writes a user message to the conversation and returns updated messages list.
  """
  def write_user_message(conversation, messages, content, opts \\ []) do
    kind = Keyword.get(opts, :kind, :chat)

    {:ok, user_msg} =
      Conversations.add_message(%{
        conversation_id: conversation.id,
        role: :user,
        content: content,
        kind: kind
      })

    {user_msg, messages ++ [user_msg]}
  end

  @doc """
  Prepares for re-invocation: updates message content, deletes subsequent
  messages, and reloads. Returns the updated messages list.
  """
  def prepare_reinvoke(conversation, message_id, new_content) do
    message = Conversations.get_message!(message_id)
    {:ok, _message} = Conversations.update_message_content(message, new_content)
    Conversations.delete_messages_after(message)
    Conversations.list_messages(conversation.id, visibility: :public)
  end

  @doc """
  Prepares for resend: deletes subsequent messages and reloads.
  Returns `{message, messages}`.
  """
  def prepare_resend(conversation, message_id) do
    message = Conversations.get_message!(message_id)
    Conversations.delete_messages_after(message)
    messages = Conversations.list_messages(conversation.id, visibility: :public)
    {message, messages}
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  def refresh_subtasks(nil), do: []
  def refresh_subtasks(invocation_id), do: Orchestration.list_subtasks(invocation_id)

  def extract_error_detail(nil), do: "The summon encountered an error."

  def extract_error_detail(%{"error" => "empty_response"}) do
    "The summon produced no response. Try resending or switching to a different spirit."
  end

  def extract_error_detail(%{"error" => "doom_loop"}) do
    "The summon got stuck in a loop repeating the same action. " <>
      "Try a different spirit or rephrase your request."
  end

  def extract_error_detail(%{"error" => "context_overflow"}) do
    "The conversation exceeded the spirit's context window. " <>
      "Start a new channel or switch to a spirit with a larger context."
  end

  def extract_error_detail(%{"error" => "budget_exceeded"}) do
    "The summon has reached its budget limit. " <>
      "Increase the budget or switch to a more affordable spirit."
  end

  def extract_error_detail(%{"error" => "quota_exceeded"}) do
    "This realm has reached its monthly token quota. " <>
      "Increase the quota in realm settings or wait for the next billing cycle."
  end

  def extract_error_detail(%{"error" => error}) when is_binary(error) do
    cond do
      String.contains?(error, "\"message\"") ->
        case Regex.run(~r/"message"\s*=>\s*"([^"]+)"/, error) do
          [_, msg] -> msg
          _ -> error
        end

      String.contains?(error, ":timeout") ->
        "Request timed out. Please try again."

      true ->
        error
    end
  end

  def extract_error_detail(_), do: "The summon encountered an error."
end
