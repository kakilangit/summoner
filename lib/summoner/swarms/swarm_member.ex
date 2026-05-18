defmodule Summoner.Swarms.SwarmMember do
  @moduledoc """
  Join schema linking agents to swarms with ordering.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Swarms.Swarm

  schema "swarm_members" do
    field :position, :integer, default: 0

    belongs_to :swarm, Swarm
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(swarm_id agent_id)a
  @optional_fields ~w(position)a

  def changeset(member, attrs) do
    member
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:swarm_id, :agent_id],
      message: "summon already in this party"
    )
    |> foreign_key_constraint(:swarm_id)
    |> foreign_key_constraint(:agent_id)
  end
end
