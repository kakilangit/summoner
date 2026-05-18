defmodule Summoner.Conversations.Content do
  @moduledoc """
  Helpers for multimodal content blocks.

  Message content is stored as a list of typed maps:

      [
        %{"type" => "text", "text" => "Hello"},
        %{"type" => "image", "media_attachment_id" => "01JXY...", "alt" => "diagram"},
        %{"type" => "video", "media_attachment_id" => "01JXZ...", "alt" => "demo"}
      ]
  """

  @max_blocks 100

  @doc """
  Extracts all text from content blocks, joined by newline.
  Returns empty string for nil or empty list.
  """
  @spec text_only([map()] | nil) :: String.t()
  def text_only(nil), do: ""
  def text_only([]), do: ""

  def text_only(blocks) when is_list(blocks) do
    blocks
    |> Enum.take(@max_blocks)
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  # Handle legacy string content (defensive — should not happen after migration)
  def text_only(str) when is_binary(str), do: str

  @doc """
  Wraps a plain string as a single text content block list.
  Returns nil for nil input, empty list for empty string.
  """
  @spec from_string(String.t() | nil) :: [map()] | nil
  def from_string(nil), do: nil
  def from_string(""), do: []
  def from_string(text) when is_binary(text), do: [%{"type" => "text", "text" => text}]

  @doc """
  Normalizes content input — accepts either string or block list.
  Used by `Conversations.add_message/1` to accept both formats.
  """
  @spec normalize(String.t() | [map()] | nil) :: [map()] | nil
  def normalize(nil), do: nil
  def normalize(content) when is_binary(content), do: from_string(content)
  def normalize(content) when is_list(content), do: Enum.take(content, @max_blocks)

  @doc """
  Returns true if any block is a media type (image or video).
  """
  @spec has_media?([map()] | nil) :: boolean()
  def has_media?(nil), do: false
  def has_media?([]), do: false

  def has_media?(blocks) when is_list(blocks) do
    Enum.any?(blocks, &(&1["type"] in ["image", "video"]))
  end

  @doc """
  Returns only media blocks (image and video).
  """
  @spec media_blocks([map()] | nil) :: [map()]
  def media_blocks(nil), do: []
  def media_blocks([]), do: []

  def media_blocks(blocks) when is_list(blocks) do
    Enum.filter(blocks, &(&1["type"] in ["image", "video"]))
  end

  @doc """
  Returns only image blocks with their attachment IDs.
  """
  @spec image_attachment_ids([map()] | nil) :: [String.t()]
  def image_attachment_ids(nil), do: []
  def image_attachment_ids([]), do: []

  def image_attachment_ids(blocks) when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "image" && &1["media_attachment_id"]))
    |> Enum.map(& &1["media_attachment_id"])
  end

  @doc """
  Converts DB-format content blocks (string keys) to Intent-format blocks (atom keys).

  Without an attachments map, image blocks become text placeholders.
  Use `to_intent_blocks/2` with a preloaded attachments map for vision support.
  """
  @spec to_intent_blocks([map()] | nil) :: [map()]
  def to_intent_blocks(nil), do: []
  def to_intent_blocks([]), do: []

  def to_intent_blocks(blocks) when is_list(blocks) do
    to_intent_blocks(blocks, %{})
  end

  @doc """
  Converts DB-format content blocks to Intent-format blocks with vision support.

  When an attachments map (`%{id => %MediaAttachment{}}`) is provided,
  image blocks are resolved to base64 content blocks for vision-capable models.
  Attachments not found in the map or with no file on disk fall back to
  text placeholders.

  Videos are always rendered as text placeholders (no model supports video input).
  """
  @spec to_intent_blocks([map()] | nil, map()) :: [map()]
  def to_intent_blocks(nil, _attachments_map), do: []
  def to_intent_blocks([], _attachments_map), do: []

  def to_intent_blocks(blocks, attachments_map)
      when is_list(blocks) and is_map(attachments_map) do
    blocks
    |> Enum.take(@max_blocks)
    |> Enum.map(&to_intent_block(&1, attachments_map))
    |> Enum.reject(&is_nil/1)
  end

  defp to_intent_block(%{"type" => "text", "text" => text}, _attachments_map) do
    %{type: :text, text: text}
  end

  defp to_intent_block(
         %{"type" => "image", "media_attachment_id" => id} = block,
         attachments_map
       ) do
    case resolve_image_to_base64(id, attachments_map) do
      {:ok, media_type, data} ->
        %{type: :image_base64, media_type: media_type, data: data}

      :fallback ->
        %{type: :text, text: "[Image: #{block["alt"] || "attached image"}]"}
    end
  end

  defp to_intent_block(%{"type" => "video"} = block, _attachments_map) do
    %{type: :text, text: "[Video: #{block["alt"] || "attached video"}]"}
  end

  defp to_intent_block(_, _attachments_map), do: nil

  defp resolve_image_to_base64(id, attachments_map) when attachments_map == %{} do
    # No attachments map provided — cannot resolve
    _ = id
    :fallback
  end

  defp resolve_image_to_base64(id, attachments_map) do
    alias Summoner.Media

    case Map.get(attachments_map, id) do
      nil ->
        :fallback

      %{status: :ready, content_type: content_type} = attachment ->
        case Media.read_file(attachment) do
          {:ok, binary} ->
            {:ok, content_type, Base.encode64(binary)}

          {:error, _} ->
            :fallback
        end

      _ ->
        :fallback
    end
  end
end
