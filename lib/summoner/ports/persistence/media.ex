defmodule Summoner.Ports.Persistence.Media do
  @moduledoc "Port for Media persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :media],
             Summoner.Adapters.Persistence.Media
           )

  # Queries
  defdelegate get_attachment!(id), to: @adapter
  defdelegate get_attachment(id), to: @adapter
  defdelegate list_conversation_attachments(conversation_id), to: @adapter
  defdelegate list_workspace_attachments(workspace_id), to: @adapter
  defdelegate list_workspace_attachments(workspace_id, opts), to: @adapter
  defdelegate get_attachments_map(ids), to: @adapter
  defdelegate workspace_storage_used(workspace_id), to: @adapter
  defdelegate pending_jobs_count(workspace_id), to: @adapter

  # Creation
  defdelegate create_pending_attachment(attrs), to: @adapter
  defdelegate create_uploaded_attachment(attrs), to: @adapter

  # Lifecycle
  defdelegate mark_ready(attachment, attrs), to: @adapter
  defdelegate mark_failed(attachment, reason), to: @adapter
  defdelegate delete_attachment(attachment), to: @adapter
  defdelegate retry_failed_attachment(attachment), to: @adapter

  # File storage
  defdelegate store_file(attachment, binary), to: @adapter
  defdelegate delete_file(attachment), to: @adapter
  defdelegate file_path(attachment), to: @adapter
  defdelegate media_url(attachment), to: @adapter
  defdelegate read_file(attachment), to: @adapter

  # Validation
  defdelegate validate_file_size(type, size), to: @adapter
  defdelegate validate_workspace_quota(workspace_id, additional_bytes), to: @adapter
  defdelegate validate_pending_limit(workspace_id), to: @adapter
  defdelegate max_file_size(type), to: @adapter
  defdelegate max_workspace_storage(), to: @adapter

  # Cleanup
  defdelegate cleanup_orphaned_files(), to: @adapter
end
