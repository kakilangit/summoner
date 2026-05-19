defmodule Summoner.Domain.Schemas.Swarm do
  @moduledoc """
  Schema for Swarms — groups of agents that collaborate.
  UI name: Party.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.SwarmMember
  alias Summoner.Domain.Schemas.Workspace

  schema "swarms" do
    field :name, :string
    field :description, :string
    field :mode, Ecto.Enum, values: [:round_robin, :relay, :directed], default: :relay
    field :max_turns, :integer, default: 20

    belongs_to :workspace, Workspace
    belongs_to :coordinator_agent, Agent
    has_many :members, SwarmMember
    has_many :agents, through: [:members, :agent]

    timestamps()
  end

  @required_fields ~w(name workspace_id)a
  @optional_fields ~w(description mode coordinator_agent_id max_turns)a

  def changeset(swarm, attrs) do
    swarm
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:mode, [:round_robin, :relay, :directed])
    |> validate_number(:max_turns, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_coordinator()
    |> unique_constraint([:workspace_id, :name],
      message: "party name already exists in this realm"
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:coordinator_agent_id)
  end

  defp validate_coordinator(changeset) do
    mode = get_field(changeset, :mode)
    coordinator = get_field(changeset, :coordinator_agent_id)

    if mode == :directed && is_nil(coordinator) do
      add_error(changeset, :coordinator_agent_id, "is required for directed mode")
    else
      changeset
    end
  end
end
