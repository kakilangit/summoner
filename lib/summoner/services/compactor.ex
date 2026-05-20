defmodule Summoner.Services.Compactor do
  @moduledoc """
  LLM-driven conversation compaction.

  When a conversation accumulates too many messages, the Compactor
  summarizes old messages into a single `kind: :summary` message
  and marks the originals as compacted. This keeps context windows
  manageable while preserving important information.

  ## Thresholds

  - `@compact_threshold` — number of chat messages before compaction triggers
  - `@keep_recent` — number of recent messages to preserve (never compacted)
  - `@max_summarize_messages` — upper bound on messages sent to the summarizer

  ## Flow

  1. Count non-compacted chat messages in the conversation
  2. If count > threshold, load messages older than the most recent N
  3. Build a summarization prompt from those messages
  4. Call inference to produce a summary
  5. Insert a `kind: :summary` message and mark originals as compacted
  """

  require Logger

  alias Arcanum.Intent
  alias Summoner.Domain.Schemas.Message
  alias Summoner.Domain.Types.Content
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Services.Inference

  @compact_threshold 40
  @keep_recent 10
  @max_summarize_messages 100

  @summarize_prompt """
  You are a conversation summarizer. Your task is to create a concise but comprehensive \
  summary of the conversation history below.

  ## Guidelines
  - Preserve all key decisions, conclusions, and action items
  - Include important technical details, file paths, and code changes mentioned
  - Note any unresolved questions or pending tasks
  - Use bullet points for clarity
  - Keep the summary under 2000 words
  - Do NOT include tool call details or intermediate reasoning — focus on outcomes
  - Write in past tense as a factual record

  ## Conversation to summarize
  """

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Checks if a conversation needs compaction and performs it if so.

  Returns `:ok` if no compaction was needed or compaction succeeded,
  `{:error, reason}` on failure.
  """
  @spec maybe_compact(String.t(), map()) :: :ok | {:error, term()}
  def maybe_compact(conversation_id, provider) do
    count = Conversations.count_messages(conversation_id)

    if count > @compact_threshold do
      compact(conversation_id, provider)
    else
      :ok
    end
  end

  @doc """
  Forces compaction of a conversation regardless of message count.
  """
  @spec compact(String.t(), map()) :: :ok | {:error, term()}
  def compact(conversation_id, provider) do
    messages = load_compactable_messages(conversation_id)

    if messages == [] do
      :ok
    else
      case summarize(messages, provider) do
        {:ok, summary} ->
          persist_summary(conversation_id, summary, messages)

        {:error, reason} ->
          Logger.warning(
            "Compaction failed for conversation #{conversation_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp load_compactable_messages(conversation_id) do
    # Load all non-compacted chat messages, ordered chronologically
    all =
      Conversations.list_messages(conversation_id, limit: @max_summarize_messages + @keep_recent)

    # Only compact chat messages (not summaries, not tool messages without context)
    chat_messages = Enum.filter(all, &(&1.kind == :chat))

    # Keep the most recent N messages — never compact those
    if Enum.count(chat_messages) > @keep_recent do
      Enum.drop(chat_messages, -@keep_recent)
      |> Enum.take(@max_summarize_messages)
    else
      []
    end
  end

  defp summarize(messages, provider) do
    transcript = format_transcript(messages)

    intent = %Intent{
      messages: [
        %{role: :system, content: Intent.text(@summarize_prompt)},
        %{role: :user, content: Intent.text(transcript)}
      ],
      model: provider.model || default_model(provider),
      tools: [],
      max_tokens: 4_096
    }

    case Inference.Gateway.chat(provider, intent) do
      {:ok, response} ->
        text = Arcanum.Response.text(response)

        if text do
          {:ok, text}
        else
          {:error, :empty_summary}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_transcript(messages) do
    messages
    |> Enum.take(@max_summarize_messages)
    |> Enum.map_join("\n\n", &format_message/1)
  end

  defp format_message(%Message{role: role, content: content}) do
    role_label = role |> to_string() |> String.upcase()
    "**#{role_label}**: #{Content.text_only(content)}"
  end

  defp format_message(%{role: role, content: content}) do
    role_label = role |> to_string() |> String.upcase()
    text = if is_list(content), do: Content.text_only(content), else: content || "[empty]"
    "**#{role_label}**: #{text}"
  end

  defp persist_summary(conversation_id, summary, compacted_messages) do
    # Insert the summary message
    {:ok, _} =
      Conversations.add_message(%{
        conversation_id: conversation_id,
        role: :system,
        kind: :summary,
        content: summary,
        visibility: :internal
      })

    # Mark the compacted messages
    ids = Enum.map(compacted_messages, & &1.id)
    Conversations.mark_compacted(ids)

    Logger.info(
      "Compacted #{Enum.count(ids)} messages into summary for conversation #{conversation_id}"
    )

    :ok
  end

  defp default_model(%{kind: "anthropic"}), do: "claude-3-5-haiku-20241022"
  defp default_model(%{kind: "deepseek"}), do: "deepseek-chat"
  defp default_model(_), do: "gpt-4.1-mini"
end
