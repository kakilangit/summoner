defmodule Summoner.A2A.A2AServer do
  @moduledoc """
  Schema for A2A server configuration — Herald.

  Each Herald exposes a single local agent via the A2A protocol.
  Manages auth, rate limiting, and skill filtering for inbound requests.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Workspaces.Workspace

  @auth_modes ~w(bearer_token api_key none)a

  schema "a2a_servers" do
    field :enabled, :boolean, default: true
    field :auth_mode, Ecto.Enum, values: @auth_modes, default: :none
    field :api_key_hash, :string
    field :rate_limit_rpm, :integer, default: 60
    field :allowed_skills, {:array, :string}, default: []

    # Virtual field for plaintext API key input (never persisted)
    field :api_key, :string, virtual: true

    belongs_to :agent, Agent
    belongs_to :workspace, Workspace

    timestamps()
  end

  @cast_fields [
    :enabled,
    :auth_mode,
    :api_key,
    :rate_limit_rpm,
    :allowed_skills,
    :agent_id,
    :workspace_id
  ]

  @required_fields [:auth_mode, :agent_id, :workspace_id]

  @doc """
  Changeset for creating or updating an A2A server (Herald).
  """
  def changeset(server, attrs) do
    server
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_number(:rate_limit_rpm, greater_than: 0, less_than_or_equal_to: 10_000)
    |> unique_constraint(:agent_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:workspace_id)
    |> maybe_hash_api_key()
    |> validate_api_key_required()
  end

  defp maybe_hash_api_key(changeset) do
    case get_change(changeset, :api_key) do
      nil -> changeset
      key -> put_change(changeset, :api_key_hash, Bcrypt.hash_pwd_salt(key))
    end
  end

  defp validate_api_key_required(changeset) do
    auth_mode = get_field(changeset, :auth_mode)
    has_hash = get_field(changeset, :api_key_hash)

    if auth_mode in [:bearer_token, :api_key] and is_nil(has_hash) do
      add_error(changeset, :api_key, "is required for #{auth_mode} auth mode")
    else
      changeset
    end
  end
end
