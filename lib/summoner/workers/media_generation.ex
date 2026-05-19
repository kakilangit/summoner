defmodule Summoner.Workers.MediaGeneration do
  @moduledoc """
  Oban worker for async media generation via Forge providers.

  Receives a pending MediaAttachment ID and a media provider ID,
  calls the Arcanum Gateway to generate the image/video, stores
  the result on disk, and transitions the attachment to `:ready`
  or `:failed`.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 2,
    priority: 2

  alias Arcanum.{Intent, Response}
  alias Summoner.Conversations
  alias Summoner.Events
  alias Summoner.Events.{MediaGenerationCompleted, MediaGenerationFailed, MediaGenerationStarted}
  alias Summoner.Inference.Gateway
  alias Summoner.Media
  alias Summoner.MediaProviders

  require Logger

  @receive_timeout 120_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "attachment_id" => attachment_id,
      "media_provider_id" => media_provider_id,
      "type" => type,
      "params" => params
    } = args

    message_id = args["message_id"]
    attachment = Media.get_attachment!(attachment_id)
    media_provider = MediaProviders.get_media_provider!(media_provider_id)

    intent = build_intent(type, media_provider, params)

    broadcast_started(attachment)

    result =
      case type do
        "image" -> Gateway.generate_image(media_provider.provider, intent, [])
        "video" -> Gateway.generate_video(media_provider.provider, intent, [])
      end

    case result do
      {:ok, %Response{content: [block | _]}} ->
        binary = resolve_binary(block)
        handle_success(attachment, binary, block, message_id, type)

      {:ok, %Response{content: []}} ->
        handle_failure(attachment, "No media items returned by provider")

      {:ok, %Response{content: nil}} ->
        handle_failure(attachment, "No media items returned by provider")

      {:error, reason} ->
        handle_failure(attachment, format_error(reason))
    end
  end

  defp handle_success(attachment, binary, block, message_id, type) do
    :ok = Media.store_file(attachment, binary)

    {:ok, ready} =
      Media.mark_ready(attachment, %{
        file_size: byte_size(binary),
        revised_prompt: block[:revised_prompt]
      })

    if message_id, do: append_media_block(message_id, ready.id, type)

    broadcast_complete(ready)
    :ok
  end

  defp handle_failure(attachment, reason) do
    Logger.warning("Media generation failed: #{reason}")
    {:ok, failed} = Media.mark_failed(attachment, reason)
    broadcast_failed(failed, reason)
    {:error, reason}
  end

  defp build_intent("image", media_provider, params) do
    %Intent{
      model: params["model"] || media_provider.default_image_model || "gpt-image-1",
      prompt: params["prompt"],
      size: params["size"] || "1024x1024",
      quality: params["quality"] || "auto",
      n: min(params["n"] || 1, 4),
      format: params["format"] || "png"
    }
  end

  defp build_intent("video", media_provider, params) do
    %Intent{
      model: params["model"] || media_provider.default_video_model || "sora",
      prompt: params["prompt"],
      size: params["size"] || "720p",
      n: 1,
      format: "mp4"
    }
  end

  defp resolve_binary(%{data: data}) when is_binary(data) and data != "", do: data

  defp resolve_binary(%{url: url}) when is_binary(url) do
    case Req.get(url, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} -> body
      {:ok, %{status: status}} -> raise "Failed to download media: HTTP #{status}"
      {:error, reason} -> raise "Failed to download media: #{inspect(reason)}"
    end
  end

  defp resolve_binary(_), do: raise("No data or URL in media response block")

  defp format_error({:api_error, status, body}) do
    "API error #{status}: #{inspect(body)}"
  end

  defp format_error({:transport_error, reason}) do
    "Transport error: #{inspect(reason)}"
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp broadcast_started(attachment) do
    Events.publish(%MediaGenerationStarted{
      workspace_id: attachment.workspace_id,
      conversation_id: attachment.conversation_id,
      attachment_id: attachment.id,
      type: attachment.type,
      prompt: attachment.prompt
    })
  end

  defp broadcast_complete(attachment) do
    Events.publish(%MediaGenerationCompleted{
      workspace_id: attachment.workspace_id,
      conversation_id: attachment.conversation_id,
      attachment_id: attachment.id,
      url: Media.media_url(attachment)
    })
  end

  defp broadcast_failed(attachment, reason) do
    Events.publish(%MediaGenerationFailed{
      workspace_id: attachment.workspace_id,
      conversation_id: attachment.conversation_id,
      attachment_id: attachment.id,
      error: reason
    })
  end

  defp append_media_block(message_id, attachment_id, type) do
    message = Conversations.get_message!(message_id)
    kind = if type == "image", do: :generate_image, else: :generate_video

    block = %{
      "type" => type,
      "media_attachment_id" => attachment_id,
      "alt" => "generated #{type}"
    }

    Conversations.add_message(%{
      conversation_id: message.conversation_id,
      role: :assistant,
      kind: kind,
      content: [block]
    })
  end
end
