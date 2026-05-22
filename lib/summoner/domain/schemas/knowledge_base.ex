defmodule Summoner.Domain.Schemas.KnowledgeBase do
  @moduledoc "Schema for knowledge bases used in retrieval-augmented generation."

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.KnowledgeBaseAgent
  alias Summoner.Domain.Schemas.KnowledgeChunk
  alias Summoner.Domain.Schemas.Workspace

  @types [:documents, :web_crawl, :database, :api]
  @strategies [:fixed, :semantic, :paragraph]
  @statuses [:pending, :indexing, :ready, :error]

  schema "knowledge_bases" do
    field :name, :string
    field :description, :string
    field :type, Ecto.Enum, values: @types
    field :config, :map, default: %{}
    field :embedding_model, :string, default: "text-embedding-3-small"
    field :chunk_strategy, Ecto.Enum, values: @strategies, default: :fixed
    field :chunk_size, :integer, default: 512
    field :chunk_overlap, :integer, default: 64
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :document_count, :integer, default: 0
    field :error_message, :string
    field :file_hashes, :map, default: %{}

    belongs_to :workspace, Workspace

    has_many :chunks, KnowledgeChunk
    has_many :knowledge_base_agents, KnowledgeBaseAgent

    timestamps()
  end

  def changeset(kb, attrs) do
    kb
    |> cast(attrs, [
      :name,
      :description,
      :type,
      :config,
      :embedding_model,
      :chunk_strategy,
      :chunk_size,
      :chunk_overlap,
      :workspace_id
    ])
    |> validate_required([:name, :type, :workspace_id])
    |> validate_number(:chunk_size, greater_than: 0)
    |> validate_number(:chunk_overlap, greater_than_or_equal_to: 0)
    |> validate_overlap_less_than_size()
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:chunk_strategy, @strategies)
    |> unique_constraint([:workspace_id, :name])
    |> foreign_key_constraint(:workspace_id)
  end

  def status_changeset(kb, attrs) do
    kb
    |> cast(attrs, [:status, :error_message, :document_count, :file_hashes])
  end

  defp validate_overlap_less_than_size(changeset) do
    overlap = get_field(changeset, :chunk_overlap)
    size = get_field(changeset, :chunk_size)

    if overlap && size && overlap >= size do
      add_error(changeset, :chunk_overlap, "must be less than chunk_size")
    else
      changeset
    end
  end
end
