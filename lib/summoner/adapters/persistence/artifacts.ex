defmodule Summoner.Adapters.Persistence.Artifacts do
  @moduledoc """
  The Artifacts context (Relics).

  Manages workspace-scoped artifacts — persistent agent outputs that
  outlive conversations. Supports versioning via parent_id chains,
  soft-delete, and pinning.
  """

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.Artifact
  alias Summoner.Repo

  @behaviour Summoner.Ports.Persistence.Artifacts.Adapter

  @doc "Creates an artifact."
  def create_artifact(%{user: _user}, attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists artifacts for a workspace (excluding soft-deleted)."
  def list_artifacts(%{user: _user}, workspace_id) do
    Artifact
    |> where([a], a.workspace_id == ^workspace_id and is_nil(a.deleted_at))
    |> order_by([a], desc: a.updated_at)
    |> Repo.all()
  end

  @doc "Lists artifacts with pagination."
  def list_artifacts_paginated(%{user: _user}, workspace_id, opts \\ []) do
    Artifact
    |> where([a], a.workspace_id == ^workspace_id and is_nil(a.deleted_at))
    |> Pagination.paginate(opts)
  end

  @doc "Gets an artifact by ID."
  def get_artifact!(%{user: _user}, workspace_id, artifact_id) do
    Artifact
    |> where([a], a.workspace_id == ^workspace_id and is_nil(a.deleted_at))
    |> Repo.get!(artifact_id)
  end

  @doc "Gets an artifact by name within a workspace."
  def get_artifact_by_name(workspace_id, name) do
    Artifact
    |> where([a], a.workspace_id == ^workspace_id and a.name == ^name and is_nil(a.deleted_at))
    |> order_by([a], desc: a.version)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Updates an artifact."
  def update_artifact(%{user: _user}, %Artifact{} = artifact, attrs) do
    artifact
    |> Artifact.changeset(attrs)
    |> Repo.update()
  end

  @doc "Soft-deletes an artifact."
  def delete_artifact(%{user: _user}, %Artifact{} = artifact) do
    artifact
    |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc "Lists artifacts for a conversation."
  def list_conversation_artifacts(conversation_id) do
    Artifact
    |> where([a], a.conversation_id == ^conversation_id and is_nil(a.deleted_at))
    |> order_by([a], desc: a.updated_at)
    |> Repo.all()
  end

  @doc "Lists all versions of an artifact (by following parent chain)."
  def list_versions(workspace_id, artifact_id) do
    # Get the artifact and find all versions with the same name
    case Repo.get(Artifact, artifact_id) do
      nil ->
        []

      artifact ->
        Artifact
        |> where(
          [a],
          a.workspace_id == ^workspace_id and a.name == ^artifact.name and is_nil(a.deleted_at)
        )
        |> order_by([a], asc: a.version)
        |> Repo.all()
    end
  end
end
