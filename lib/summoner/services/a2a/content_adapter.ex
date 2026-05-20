defmodule Summoner.Services.A2A.ContentAdapter do
  @moduledoc """
  Converts between A2A protocol parts and Summoner content blocks.

  ## Inbound (A2A -> Summoner)

  | A2A Part       | Content Block                                         |
  |----------------|-------------------------------------------------------|
  | `TextPart`     | `%{"type" => "text", "text" => "..."}`                |
  | `FilePart`     | `%{"type" => "text", "text" => "[file](uri)"}`        |
  | `DataPart`     | `%{"type" => "text", "text" => "```json\\n...\\n```"}` |

  ## Outbound (Summoner -> A2A)

  | Content Block     | A2A Part         |
  |-------------------|------------------|
  | `type: "text"`    | `A2A.Part.Text`  |
  | `type: "image"`   | `A2A.Part.Text`  (placeholder, no URL resolution in v1) |
  | `type: "video"`   | `A2A.Part.Text`  (placeholder) |
  """

  alias A2A.Message
  alias A2A.Part

  @doc """
  Converts A2A message parts to Summoner content blocks.
  """
  @spec parts_to_content([Part.t()]) :: [map()]
  def parts_to_content(parts) when is_list(parts) do
    Enum.map(parts, &part_to_block/1)
  end

  @doc """
  Converts Summoner content blocks to A2A message parts.
  """
  @spec content_to_parts([map()] | nil) :: [Part.t()]
  def content_to_parts(nil), do: []
  def content_to_parts([]), do: []

  def content_to_parts(blocks) when is_list(blocks) do
    Enum.map(blocks, &block_to_part/1)
  end

  @doc """
  Converts an A2A Message to Summoner message attributes.
  """
  @spec message_to_attrs(A2A.Message.t()) :: map()
  def message_to_attrs(%Message{} = message) do
    %{
      role: a2a_role_to_summoner(message.role),
      content: parts_to_content(message.parts)
    }
  end

  @doc """
  Creates an A2A Message from Summoner content blocks.
  """
  @spec content_to_message([map()] | nil, :user | :agent) :: Message.t()
  def content_to_message(blocks, role) do
    parts = content_to_parts(blocks)

    case role do
      :user -> Message.new_user(parts)
      :agent -> Message.new_agent(parts)
    end
  end

  # -------------------------------------------------------------------
  # Inbound: A2A Part -> Content Block
  # -------------------------------------------------------------------

  defp part_to_block(%Part.Text{text: text}) do
    %{"type" => "text", "text" => text}
  end

  defp part_to_block(%Part.File{file: file}) do
    label = file.name || "file"
    uri = file.uri || "(inline data)"
    %{"type" => "text", "text" => "[#{label}](#{uri})"}
  end

  defp part_to_block(%Part.Data{data: data}) do
    json = Jason.encode!(data, pretty: true)
    %{"type" => "text", "text" => "```json\n#{json}\n```"}
  end

  # -------------------------------------------------------------------
  # Outbound: Content Block -> A2A Part
  # -------------------------------------------------------------------

  defp block_to_part(%{"type" => "text", "text" => text}) do
    Part.Text.new(text)
  end

  defp block_to_part(%{"type" => "image"} = block) do
    alt = block["alt"] || "attached image"
    Part.Text.new("[Image: #{alt}]")
  end

  defp block_to_part(%{"type" => "video"} = block) do
    alt = block["alt"] || "attached video"
    Part.Text.new("[Video: #{alt}]")
  end

  defp block_to_part(_unknown) do
    Part.Text.new("")
  end

  # -------------------------------------------------------------------
  # Role Mapping
  # -------------------------------------------------------------------

  defp a2a_role_to_summoner(:user), do: :user
  defp a2a_role_to_summoner(:agent), do: :assistant
end
