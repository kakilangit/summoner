defmodule Summoner.Domain.Schemas.RemoteAgent do
  @moduledoc """
  Schema for remote agent configuration — A2A client settings.

  Each remote agent connects to an external A2A-compliant agent via its
  Agent Card URL. This is the detail table for agents with `type: :remote`.

  Uses the parent `agents.id` as its primary key (`agent_id`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Secret

  @primary_key {:agent_id, Nulid.Ecto, autogenerate: false}
  @foreign_key_type Nulid.Ecto
  @timestamps_opts [type: :utc_datetime_usec]

  @auth_modes ~w(bearer_token api_key oauth2 none)a
  @statuses ~w(online offline unknown)a

  schema "remote_agents" do
    field :agent_card_url, :string
    field :cached_agent_card, :map
    field :auth_mode, Ecto.Enum, values: @auth_modes, default: :none
    field :card_refreshed_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: @statuses, default: :unknown
    field :timeout_s, :integer, default: 300

    belongs_to :agent, Agent, references: :id, define_field: false
    belongs_to :api_key_secret, Secret
  end

  @cast_fields [
    :agent_card_url,
    :cached_agent_card,
    :auth_mode,
    :card_refreshed_at,
    :status,
    :timeout_s,
    :api_key_secret_id
  ]

  @required_fields [:agent_card_url]

  @doc """
  Changeset for creating or updating a remote agent's configuration.
  """
  def changeset(remote_agent, attrs) do
    remote_agent
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_number(:timeout_s, greater_than: 0, less_than_or_equal_to: 3_600)
    |> foreign_key_constraint(:api_key_secret_id)
  end
end
