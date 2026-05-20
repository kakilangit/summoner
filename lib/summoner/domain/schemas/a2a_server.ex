defmodule Summoner.Domain.Schemas.A2AServer do
  @moduledoc """
  Schema for A2A server configuration — Herald.

  Each Herald exposes a single local agent via the A2A protocol.
  Access is either public (no auth) or protected (token-based).
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Workspace

  @access_modes ~w(public protected)a

  schema "a2a_servers" do
    field :enabled, :boolean, default: true
    field :access_mode, Ecto.Enum, values: @access_modes, default: :public
    field :allowed_skills, {:array, :string}, default: []

    belongs_to :agent, Agent
    belongs_to :workspace, Workspace

    timestamps()
  end

  @cast_fields [:enabled, :access_mode, :allowed_skills, :agent_id, :workspace_id]
  @required_fields [:agent_id, :workspace_id]

  @doc """
  Changeset for creating or updating an A2A server (Herald).
  """
  def changeset(server, attrs) do
    server
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:agent_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:workspace_id)
  end
end
