defmodule SummonerWeb.MediaRetry do
  @moduledoc """
  Shared retry logic for failed media generations, used by both
  ConversationLive.Show and SwarmLive.Session.
  """

  alias Summoner.Adapters.Persistence.Media
  alias Summoner.Adapters.Persistence.MediaProviders
  alias Summoner.Adapters.Workers.MediaGeneration

  import Phoenix.LiveView, only: [put_flash: 3]

  @doc """
  Handles the retry_media_generation event. Returns `{:noreply, socket}`.
  """
  def handle_retry(attachment_id, socket) do
    case Media.get_attachment(attachment_id) do
      %{status: :failed} = attachment -> do_retry(attachment, socket)
      _ -> {:noreply, put_flash(socket, :error, "Artifact not found or not failed.")}
    end
  end

  defp do_retry(attachment, socket) do
    case Media.retry_failed_attachment(attachment) do
      {:ok, new_attachment} ->
        enqueue_retry(attachment, new_attachment, socket)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not retry artifact.")}
    end
  end

  defp enqueue_retry(original, new_attachment, socket) do
    case MediaProviders.get_default_media_provider(original.workspace_id, original.type) do
      nil ->
        {:noreply, put_flash(socket, :error, "No forge configured for retry.")}

      media_provider ->
        %{
          "attachment_id" => new_attachment.id,
          "media_provider_id" => media_provider.id,
          "message_id" => original.message_id,
          "type" => to_string(new_attachment.type),
          "params" => %{"prompt" => new_attachment.prompt}
        }
        |> MediaGeneration.new()
        |> Oban.insert()

        {:noreply, put_flash(socket, :info, "Retrying artifact...")}
    end
  end
end
