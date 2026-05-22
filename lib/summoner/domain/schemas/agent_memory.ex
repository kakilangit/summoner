defmodule Summoner.Domain.Schemas.AgentMemory do
  @moduledoc """
  Schema for agent memories.

  Stores learned facts, preferences, procedures, and corrections
  that an agent accumulates over conversations. Supports vector
  similarity search via pgvector embeddings and confidence-based
  decay for memory management.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Conversation
  alias Summoner.Domain.Schemas.Workspace

  @memory_types [:fact, :preference, :procedure, :correction]

  schema "agent_memories" do
    field :type, Ecto.Enum, values: @memory_types
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :confidence, :float, default: 1.0
    field :last_accessed_at, :utc_datetime_usec
    field :access_count, :integer, default: 0

    field :similarity, :float, virtual: true

    belongs_to :agent, Agent
    belongs_to :workspace, Workspace
    belongs_to :source_conversation, Conversation

    timestamps()
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :type,
      :content,
      :confidence,
      :source_conversation_id,
      :workspace_id,
      :agent_id
    ])
    |> validate_required([:type, :content, :workspace_id, :agent_id])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:type, @memory_types)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:source_conversation_id)
  end

  def embedding_changeset(memory, attrs) do
    memory
    |> cast(attrs, [:embedding])
  end
end
