defmodule Summoner.Ports.Persistence.Artifacts.Adapter do
  @moduledoc "Behaviour for artifacts persistence operations."

  @callback create_artifact(map(), map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback list_artifacts(map(), String.t()) :: [struct()]
  @callback list_artifacts_paginated(map(), String.t(), keyword()) :: struct()
  @callback get_artifact!(map(), String.t(), String.t()) :: struct()
  @callback get_artifact_by_name(String.t(), String.t()) :: struct() | nil
  @callback update_artifact(map(), struct(), map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback delete_artifact(map(), struct()) :: {:ok, struct()} | {:error, term()}
  @callback list_conversation_artifacts(String.t()) :: [struct()]
  @callback list_versions(String.t(), String.t()) :: [struct()]
end
