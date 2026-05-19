defmodule Summoner.Adapters.Persistence.Media do
  @moduledoc """
  Media generation, storage, and retrieval context (Artifacts).

  Manages media attachments — images and videos that are either
  user-uploaded (Offered) or AI-generated (Forged). Handles
  file storage on local disk and lifecycle transitions.
  """

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.MediaAttachment
  alias Summoner.Repo

  @max_file_size_image 10_485_760
  @max_file_size_video 104_857_600
  @max_workspace_storage 1_073_741_824
  @max_pending_jobs_per_workspace 10
  @max_attachments_per_query 100

  @upload_base_dir "priv/static/uploads"

  # -------------------------------------------------------------------
  # Queries
  # -------------------------------------------------------------------

  @doc """
  Gets a single attachment by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_attachment!(id) do
    Repo.get!(MediaAttachment, id)
  end

  @doc """
  Gets an attachment by ID, returns nil if not found.
  """
  def get_attachment(id) do
    Repo.get(MediaAttachment, id)
  end

  @doc """
  Lists attachments for a conversation, ordered by creation time.
  """
  def list_conversation_attachments(conversation_id) do
    MediaAttachment
    |> where([a], a.conversation_id == ^conversation_id)
    |> order_by([a], asc: a.inserted_at)
    |> limit(@max_attachments_per_query)
    |> Repo.all()
  end

  @doc """
  Lists attachments for a workspace with optional filters.

  Options:
  - `:type` — filter by `:image` or `:video`
  - `:source` — filter by `:generated` or `:uploaded`
  - `:status` — filter by `:pending`, `:ready`, or `:failed`
  - `:after` — only attachments created after this `DateTime`
  - `:before` — only attachments created before this `DateTime`
  - `:limit` — max results (default 50)
  """
  def list_workspace_attachments(workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    MediaAttachment
    |> where([a], a.workspace_id == ^workspace_id)
    |> maybe_filter(:type, Keyword.get(opts, :type))
    |> maybe_filter(:source, Keyword.get(opts, :source))
    |> maybe_filter(:status, Keyword.get(opts, :status))
    |> maybe_filter(:after, Keyword.get(opts, :after))
    |> maybe_filter(:before, Keyword.get(opts, :before))
    |> order_by([a], desc: a.inserted_at)
    |> limit(^min(limit, @max_attachments_per_query))
    |> Repo.all()
  end

  @doc """
  Returns a map of attachment_id => attachment for a list of IDs.
  Efficient batch lookup for rendering messages with media blocks.
  """
  def get_attachments_map(ids) when is_list(ids) do
    ids = Enum.take(ids, @max_attachments_per_query)

    MediaAttachment
    |> where([a], a.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  def get_attachments_map([]), do: %{}

  @doc """
  Returns total storage used by a workspace in bytes.
  """
  def workspace_storage_used(workspace_id) do
    MediaAttachment
    |> where([a], a.workspace_id == ^workspace_id)
    |> where([a], a.status == :ready)
    |> Repo.aggregate(:sum, :file_size) || 0
  end

  @doc """
  Returns count of pending jobs for a workspace.
  """
  def pending_jobs_count(workspace_id) do
    MediaAttachment
    |> where([a], a.workspace_id == ^workspace_id)
    |> where([a], a.status == :pending)
    |> Repo.aggregate(:count)
  end

  # -------------------------------------------------------------------
  # Creation
  # -------------------------------------------------------------------

  @doc """
  Creates a pending attachment for async generation.
  """
  def create_pending_attachment(attrs) do
    attrs = Map.put(attrs, :status, :pending)

    %MediaAttachment{}
    |> MediaAttachment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a ready attachment for a user-uploaded file.
  The file must already be stored on disk.
  """
  def create_uploaded_attachment(attrs) do
    attrs =
      attrs
      |> Map.put(:source, :uploaded)
      |> Map.put(:status, :ready)

    %MediaAttachment{}
    |> MediaAttachment.changeset(attrs)
    |> Repo.insert()
  end

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @doc """
  Marks an attachment as ready after successful file storage.
  """
  def mark_ready(%MediaAttachment{} = attachment, attrs) do
    attachment
    |> MediaAttachment.ready_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks an attachment as failed.
  """
  def mark_failed(%MediaAttachment{} = attachment, reason) do
    attachment
    |> MediaAttachment.failed_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Deletes an attachment and its file from disk.
  """
  def delete_attachment(%MediaAttachment{} = attachment) do
    delete_file(attachment)
    Repo.delete(attachment)
  end

  @doc """
  Retries a failed attachment by creating a new pending attachment
  with the same parameters. Returns `{:ok, new_attachment}` or `{:error, changeset}`.

  Only works on failed attachments.
  """
  def retry_failed_attachment(%MediaAttachment{status: :failed} = attachment) do
    create_pending_attachment(%{
      workspace_id: attachment.workspace_id,
      conversation_id: attachment.conversation_id,
      source: :generated,
      type: attachment.type,
      filename:
        "generated_#{System.unique_integer([:positive])}#{extension_from_content_type(attachment.content_type)}",
      content_type: attachment.content_type,
      prompt: attachment.prompt,
      model_name: attachment.model_name,
      provider_name: attachment.provider_name,
      metadata: attachment.metadata || %{}
    })
  end

  def retry_failed_attachment(_), do: {:error, :not_failed}

  # -------------------------------------------------------------------
  # File storage
  # -------------------------------------------------------------------

  @doc """
  Stores a binary file to disk for the given attachment.
  Returns `:ok` or `{:error, reason}`.
  """
  def store_file(%MediaAttachment{} = attachment, binary) when is_binary(binary) do
    path = file_path(attachment)
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir) do
      File.write(path, binary)
    end
  end

  @doc """
  Deletes the file for an attachment from disk.
  Returns `:ok` (idempotent — ignores missing files).
  """
  def delete_file(%MediaAttachment{} = attachment) do
    path = file_path(attachment)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc """
  Returns the file system path for an attachment's stored file.
  """
  def file_path(%MediaAttachment{} = attachment) do
    ext = extension_from_content_type(attachment.content_type)
    Path.join([@upload_base_dir, attachment.workspace_id, "#{attachment.id}#{ext}"])
  end

  @doc """
  Returns the public URL path for serving an attachment.
  """
  def media_url(%MediaAttachment{} = attachment) do
    ext = extension_from_content_type(attachment.content_type)
    "/uploads/#{attachment.workspace_id}/#{attachment.id}#{ext}"
  end

  @doc """
  Reads the file for an attachment from disk.
  Returns `{:ok, binary}` or `{:error, reason}`.
  """
  def read_file(%MediaAttachment{} = attachment) do
    File.read(file_path(attachment))
  end

  # -------------------------------------------------------------------
  # Validation
  # -------------------------------------------------------------------

  @doc """
  Validates that a file size is within limits for the given type.
  """
  def validate_file_size(:image, size), do: size <= @max_file_size_image
  def validate_file_size(:video, size), do: size <= @max_file_size_video

  @doc """
  Validates that workspace storage quota is not exceeded.
  """
  def validate_workspace_quota(workspace_id, additional_bytes) do
    used = workspace_storage_used(workspace_id)
    used + additional_bytes <= @max_workspace_storage
  end

  @doc """
  Validates that the workspace hasn't exceeded pending job limit.
  """
  def validate_pending_limit(workspace_id) do
    pending_jobs_count(workspace_id) < @max_pending_jobs_per_workspace
  end

  @doc """
  Returns the maximum file size for a given media type.
  """
  def max_file_size(:image), do: @max_file_size_image
  def max_file_size(:video), do: @max_file_size_video

  @doc """
  Returns the maximum workspace storage quota.
  """
  def max_workspace_storage, do: @max_workspace_storage

  # -------------------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------------------

  @doc """
  Removes files on disk that have no corresponding attachment record.
  Returns the count of orphaned files removed.
  """
  def cleanup_orphaned_files do
    upload_dir = @upload_base_dir

    case File.ls(upload_dir) do
      {:ok, workspace_dirs} ->
        Enum.reduce(workspace_dirs, 0, fn ws_dir, count ->
          full_dir = Path.join(upload_dir, ws_dir)
          count + cleanup_workspace_dir(full_dir)
        end)

      {:error, :enoent} ->
        0
    end
  end

  defp cleanup_workspace_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        Enum.count(files, &orphaned_file?(dir, &1))

      {:error, _} ->
        0
    end
  end

  defp orphaned_file?(dir, file) do
    id = Path.rootname(file)

    case get_attachment(id) do
      nil ->
        File.rm(Path.join(dir, file))
        true

      _ ->
        false
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :type, type), do: where(query, [a], a.type == ^type)
  defp maybe_filter(query, :source, source), do: where(query, [a], a.source == ^source)
  defp maybe_filter(query, :status, status), do: where(query, [a], a.status == ^status)
  defp maybe_filter(query, :after, dt), do: where(query, [a], a.inserted_at >= ^dt)
  defp maybe_filter(query, :before, dt), do: where(query, [a], a.inserted_at <= ^dt)

  defp extension_from_content_type("image/jpeg"), do: ".jpg"
  defp extension_from_content_type("image/png"), do: ".png"
  defp extension_from_content_type("image/gif"), do: ".gif"
  defp extension_from_content_type("image/webp"), do: ".webp"
  defp extension_from_content_type("video/mp4"), do: ".mp4"
  defp extension_from_content_type("video/webm"), do: ".webm"
  defp extension_from_content_type(_), do: ".bin"
end
