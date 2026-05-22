defmodule Summoner.Domain.Schemas.KnowledgeBaseAgent do
  @moduledoc "Join schema linking agents to knowledge bases."

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.KnowledgeBase

  schema "knowledge_base_agents" do
    belongs_to :knowledge_base, KnowledgeBase
    belongs_to :agent, Agent

    timestamps()
  end

  def changeset(kba, attrs) do
    kba
    |> cast(attrs, [:knowledge_base_id, :agent_id])
    |> validate_required([:knowledge_base_id, :agent_id])
    |> unique_constraint([:knowledge_base_id, :agent_id])
    |> foreign_key_constraint(:knowledge_base_id)
    |> foreign_key_constraint(:agent_id)
  end
end
