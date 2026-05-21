defmodule Summoner.Domain.Schemas.Artifact do
  @moduledoc """
  Schema for workspace-scoped artifacts (Relics).

  Artifacts are persistent outputs from agent invocations — documents,
  code files, datasets, reports — that outlive conversations. They
  support versioning via `parent_id` chains and soft-delete.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  @types ~w(document code dataset image report)

  schema "artifacts" do
    field :name, :string
    field :type, :string
    field :content, :string
    field :content_type, :string, default: "text/markdown"
    field :version, :integer, default: 1
    field :metadata, :map, default: %{}
    field :pinned, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :parent, __MODULE__
    belongs_to :conversation, Summoner.Domain.Schemas.Conversation
    belongs_to :agent, Summoner.Domain.Schemas.Agent
    belongs_to :workspace, Summoner.Domain.Schemas.Workspace

    timestamps()
  end

  @cast_fields ~w(name type content content_type version metadata pinned parent_id conversation_id agent_id workspace_id)a

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :type, :workspace_id])
    |> validate_inclusion(:type, @types)
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc "Returns the list of valid artifact types."
  def types, do: @types
end
