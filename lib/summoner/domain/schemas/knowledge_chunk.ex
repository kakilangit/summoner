defmodule Summoner.Domain.Schemas.KnowledgeChunk do
  @moduledoc "Schema for knowledge base chunks with pgvector embeddings."

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.KnowledgeBase
  alias Summoner.Domain.Schemas.Workspace

  schema "knowledge_chunks" do
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}
    field :document_name, :string

    field :similarity, :float, virtual: true

    belongs_to :knowledge_base, KnowledgeBase
    belongs_to :workspace, Workspace

    timestamps()
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:content, :metadata, :document_name, :knowledge_base_id, :workspace_id])
    |> validate_required([:content, :document_name, :knowledge_base_id, :workspace_id])
    |> foreign_key_constraint(:knowledge_base_id)
    |> foreign_key_constraint(:workspace_id)
  end

  def embedding_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:embedding])
  end
end
