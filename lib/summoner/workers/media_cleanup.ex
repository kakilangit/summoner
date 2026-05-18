defmodule Summoner.Workers.MediaCleanup do
  @moduledoc """
  Daily Oban cron worker that removes orphaned media files from disk.

  Walks the upload directory and deletes any file whose attachment ID
  has no corresponding record in the database. Also purges failed
  attachments older than 7 days.
  """

  use Oban.Worker, queue: :reaper, max_attempts: 1

  import Ecto.Query, warn: false

  alias Summoner.Media
  alias Summoner.Media.MediaAttachment
  alias Summoner.Repo

  require Logger

  @max_failed_age_days 7
  @max_failed_batch 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    orphaned = Media.cleanup_orphaned_files()
    failed = purge_stale_failed()

    Logger.info(
      "MediaCleanup: removed #{orphaned} orphaned files, #{failed} stale failed records"
    )

    :ok
  end

  defp purge_stale_failed do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@max_failed_age_days, :day)
      |> DateTime.truncate(:second)

    stale =
      MediaAttachment
      |> where([a], a.status == :failed)
      |> where([a], a.inserted_at < ^cutoff)
      |> limit(@max_failed_batch)
      |> Repo.all()

    Enum.each(stale, fn attachment ->
      Media.delete_file(attachment)
      Repo.delete(attachment)
    end)

    length(stale)
  end
end
