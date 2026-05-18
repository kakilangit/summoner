defmodule Summoner.Skills.AgentSkill do
  @moduledoc """
  Join schema linking agents to skills.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Skills.Skill

  schema "agent_skills" do
    belongs_to :agent, Agent
    belongs_to :skill, Skill

    timestamps(updated_at: false)
  end

  def changeset(agent_skill, attrs) do
    agent_skill
    |> cast(attrs, [:agent_id, :skill_id])
    |> validate_required([:agent_id, :skill_id])
    |> unique_constraint([:agent_id, :skill_id])
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:skill_id)
  end
end
