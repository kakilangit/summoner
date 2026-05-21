defmodule Summoner.Ports.Persistence.Artifacts do
  @moduledoc "Port for artifacts persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :artifacts],
             Summoner.Adapters.Persistence.Artifacts
           )

  defdelegate create_artifact(scope, attrs), to: @adapter
  defdelegate list_artifacts(scope, workspace_id), to: @adapter
  defdelegate list_artifacts_paginated(scope, workspace_id, opts), to: @adapter
  defdelegate get_artifact!(scope, workspace_id, artifact_id), to: @adapter
  defdelegate get_artifact_by_name(workspace_id, name), to: @adapter
  defdelegate update_artifact(scope, artifact, attrs), to: @adapter
  defdelegate delete_artifact(scope, artifact), to: @adapter
  defdelegate list_conversation_artifacts(conversation_id), to: @adapter
  defdelegate list_versions(workspace_id, artifact_id), to: @adapter
end
