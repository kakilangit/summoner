defmodule Summoner.Adapters.Persistence.Conversations do
  @moduledoc """
  The Conversations context.

  Manages conversations, participants, and messages within workspaces.
  """

  @behaviour Summoner.Ports.Persistence.Conversations.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Agents
  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Adapters.Persistence.Workspaces
  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.{Conversation, ConversationParticipant, Message}
  alias Summoner.Domain.Types.Content
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # Conversations
  # -------------------------------------------------------------------

  @doc """
  Creates a conversation and adds the primary agent as the first participant.
  """
  def create_conversation(%{user: user}, attrs) do
    agent_id = attrs[:primary_agent_id] || attrs["primary_agent_id"]

    if agent_id && agent_deleted?(agent_id) do
      {:error,
       %Ecto.Changeset{
         action: :insert,
         errors: [primary_agent_id: {"cannot start a channel with a deleted summon", []}],
         valid?: false
       }}
    else
      attrs
      |> Map.put(:user_id, user.id)
      |> maybe_add_inference_snapshot()
      |> insert_conversation()
    end
  end

  @doc """
  Creates a system-owned conversation (no user).

  Used by pipelines for persistent cross-run context.
  """
  def create_system_conversation(attrs) do
    attrs
    |> maybe_add_inference_snapshot()
    |> insert_conversation()
  end

  defp insert_conversation(attrs) do
    Repo.transact(fn ->
      with {:ok, conversation} <-
             %Conversation{}
             |> Conversation.changeset(attrs)
             |> Repo.insert(),
           {:ok, _participant} <-
             add_participant(conversation.id, conversation.primary_agent_id) do
        {:ok, conversation}
      end
    end)
  end

  @doc """
  Lists conversations for a workspace, ordered by most recent first.
  """
  def list_conversations(%{user: _user}, workspace_id) do
    Conversation
    |> Workspaces.where_workspace(workspace_id)
    |> where([c], c.kind == :chat)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists conversations for a workspace with pagination.
  """
  def list_conversations_paginated(%{user: _user}, workspace_id, opts \\ []) do
    Conversation
    |> Workspaces.where_workspace(workspace_id)
    |> where([c], c.kind == :chat)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single conversation scoped to a workspace.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_conversation!(%{user: _user}, workspace_id, conversation_id) do
    Conversation
    |> Workspaces.where_workspace(workspace_id)
    |> Repo.get!(conversation_id)
    |> Repo.preload(primary_agent: [:remote_agent, local_agent: :provider])
  end

  @doc """
  Updates the primary agent for a conversation.
  """
  def update_primary_agent(%{user: _user}, %Conversation{} = conversation, agent_id) do
    if agent_deleted?(agent_id) do
      {:error,
       %Ecto.Changeset{
         action: :update,
         errors: [primary_agent_id: {"cannot switch to a deleted summon", []}],
         valid?: false
       }}
    else
      conversation
      |> Conversation.update_changeset(%{primary_agent_id: agent_id})
      |> Repo.update()
    end
  end

  @doc """
  Updates a conversation's title.
  """
  def update_conversation(%{user: _user}, %Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation and all its messages and participants.

  Invocations referencing this conversation will have their
  `conversation_id` set to nil (nilified).
  """
  def delete_conversation(%{user: _user}, %Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # -------------------------------------------------------------------
  # Participants
  # -------------------------------------------------------------------

  @doc """
  Adds an agent as a participant to a conversation.

  Returns `{:ok, participant}` or `{:error, changeset}`.
  Idempotent — returns error changeset with unique constraint if already joined.
  """
  def add_participant(conversation_id, agent_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_id: conversation_id,
      agent_id: agent_id
    })
    |> Repo.insert()
  end

  @doc """
  Lists participants for a conversation.
  """
  def list_participants(conversation_id) do
    ConversationParticipant
    |> where([p], p.conversation_id == ^conversation_id)
    |> order_by([p], asc: p.joined_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Messages
  # -------------------------------------------------------------------

  @doc """
  Adds a message to a conversation.
  """
  def add_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Soft-deletes a message by setting `deleted_at`.
  """
  def soft_delete_message(%Message{} = message) do
    message
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
    |> Repo.update()
  end

  @doc """
  Restores a soft-deleted message by clearing `deleted_at`.
  """
  def restore_message(%Message{} = message) do
    message
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Gets a single message by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_message!(message_id) do
    Repo.get!(Message, message_id)
  end

  @doc """
  Updates the content of a message. Accepts string or block list.
  """
  def update_message_content(%Message{} = message, content) do
    normalized = Content.normalize(content)

    message
    |> Ecto.Changeset.change(content: normalized)
    |> Repo.update()
  end

  @doc """
  Hard-deletes all messages in a conversation inserted after the given message.

  Used by the resend feature to cascade-remove subsequent messages
  before re-invoking the agent.
  """
  def delete_messages_after(%Message{} = message) do
    Message
    |> where([m], m.conversation_id == ^message.conversation_id)
    |> where([m], m.inserted_at > ^message.inserted_at)
    |> Repo.delete_all()
  end

  @doc """
  Lists messages for a conversation, ordered chronologically.

  Excludes soft-deleted and compacted messages. Summary messages
  are always included regardless of visibility filter.

  Options:
  - `:limit` — max messages to return (default 50)
  - `:visibility` — filter by visibility (`:public`, `:internal`, or `nil` for all)
  """
  def list_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    visibility = Keyword.get(opts, :visibility)

    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> where([m], is_nil(m.deleted_at))
    |> where([m], is_nil(m.compacted_at))
    |> maybe_filter_visibility(visibility)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Returns the most recent summary message for a conversation, or nil.
  """
  def latest_summary(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> where([m], m.kind == :summary)
    |> where([m], is_nil(m.deleted_at))
    |> order_by([m], desc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Counts non-deleted, non-compacted chat messages in a conversation.
  """
  def count_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> where([m], is_nil(m.deleted_at))
    |> where([m], is_nil(m.compacted_at))
    |> where([m], m.kind == :chat)
    |> Repo.aggregate(:count)
  end

  @doc """
  Marks messages as compacted (they were summarized into a summary message).

  Returns `{count, nil}`.
  """
  def mark_compacted(message_ids) when is_list(message_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Message
    |> where([m], m.id in ^message_ids)
    |> Repo.update_all(set: [compacted_at: now])
  end

  # -------------------------------------------------------------------
  # Export
  # -------------------------------------------------------------------

  @max_export_messages 10_000

  @doc """
  Exports a conversation as a Markdown string.

  Only includes non-deleted, non-compacted, public chat messages.
  Messages are ordered chronologically. Agent names are resolved
  via preloading when available.

  Options:
  - `:title` — override the conversation title in the header
  """
  def export_as_markdown(conversation_id, opts \\ []) do
    messages =
      Message
      |> where([m], m.conversation_id == ^conversation_id)
      |> where([m], is_nil(m.deleted_at))
      |> where([m], is_nil(m.compacted_at))
      |> where([m], m.visibility == :public)
      |> where([m], m.kind == :chat)
      |> order_by([m], asc: m.inserted_at)
      |> limit(@max_export_messages)
      |> Repo.all()
      |> Repo.preload(:agent)

    title = Keyword.get(opts, :title, "Conversation")
    format_markdown(title, messages)
  end

  defp format_markdown(title, messages) do
    header = "# #{title}\n\n"

    body =
      Enum.map_join(messages, "\n\n---\n\n", &format_message/1)

    header <> body
  end

  alias Summoner.Services.TimeZone

  defp format_message(%Message{role: :user} = msg) do
    timestamp = TimeZone.format(msg.inserted_at)
    "**User** _#{timestamp}_\n\n#{Content.text_only(msg.content)}"
  end

  defp format_message(%Message{} = msg) do
    name = agent_display_name(msg)
    timestamp = TimeZone.format(msg.inserted_at)
    "**#{name}** _#{timestamp}_\n\n#{Content.text_only(msg.content)}"
  end

  defp agent_display_name(%Message{agent: %{name: name}}) when is_binary(name), do: name
  defp agent_display_name(%Message{role: :assistant}), do: "Assistant"
  defp agent_display_name(%Message{role: :system}), do: "System"
  defp agent_display_name(%Message{role: :tool}), do: "Tool"
  defp agent_display_name(_), do: "Unknown"

  defp maybe_filter_visibility(query, nil), do: query

  defp maybe_filter_visibility(query, visibility) do
    where(query, [m], m.visibility == ^visibility)
  end

  defp maybe_add_inference_snapshot(%{provider_name: _, model_name: _} = attrs), do: attrs

  defp maybe_add_inference_snapshot(attrs) do
    agent_id = attrs[:primary_agent_id] || attrs["primary_agent_id"]

    if agent_id do
      agent = Agents.get_agent_with_provider!(agent_id)
      Map.merge(attrs, Agent.inference_snapshot(agent))
    else
      attrs
    end
  end

  defp agent_deleted?(agent_id) do
    case Repo.get(Agent, agent_id) do
      %Agent{deleted_at: deleted_at} when not is_nil(deleted_at) -> true
      _ -> false
    end
  end
end
