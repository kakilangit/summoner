defmodule Summoner.Ports.Persistence.Media.Adapter do
  @moduledoc "Behaviour for Media persistence operations."

  alias Summoner.Domain.Schemas.MediaAttachment

  # Queries
  @callback get_attachment!(String.t()) :: MediaAttachment.t()
  @callback get_attachment(String.t()) :: MediaAttachment.t() | nil
  @callback list_conversation_attachments(String.t()) :: [MediaAttachment.t()]
  @callback list_workspace_attachments(String.t()) :: [MediaAttachment.t()]
  @callback list_workspace_attachments(String.t(), keyword()) :: [MediaAttachment.t()]
  @callback get_attachments_map([String.t()]) :: %{String.t() => MediaAttachment.t()}
  @callback workspace_storage_used(String.t()) :: non_neg_integer()
  @callback pending_jobs_count(String.t()) :: non_neg_integer()

  # Creation
  @callback create_pending_attachment(map()) ::
              {:ok, MediaAttachment.t()} | {:error, Ecto.Changeset.t()}
  @callback create_uploaded_attachment(map()) ::
              {:ok, MediaAttachment.t()} | {:error, Ecto.Changeset.t()}

  # Lifecycle
  @callback mark_ready(MediaAttachment.t(), map()) ::
              {:ok, MediaAttachment.t()} | {:error, Ecto.Changeset.t()}
  @callback mark_failed(MediaAttachment.t(), String.t()) ::
              {:ok, MediaAttachment.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_attachment(MediaAttachment.t()) ::
              {:ok, MediaAttachment.t()} | {:error, Ecto.Changeset.t()}
  @callback retry_failed_attachment(MediaAttachment.t()) ::
              {:ok, MediaAttachment.t()} | {:error, term()}

  # File storage
  @callback store_file(MediaAttachment.t(), binary()) :: :ok | {:error, term()}
  @callback delete_file(MediaAttachment.t()) :: :ok | {:error, term()}
  @callback file_path(MediaAttachment.t()) :: String.t()
  @callback media_url(MediaAttachment.t()) :: String.t()
  @callback read_file(MediaAttachment.t()) :: {:ok, binary()} | {:error, term()}

  # Validation
  @callback validate_file_size(atom(), non_neg_integer()) :: boolean()
  @callback validate_workspace_quota(String.t(), non_neg_integer()) :: boolean()
  @callback validate_pending_limit(String.t()) :: boolean()
  @callback max_file_size(atom()) :: non_neg_integer()
  @callback max_workspace_storage() :: non_neg_integer()

  # Cleanup
  @callback cleanup_orphaned_files() :: non_neg_integer()
end
