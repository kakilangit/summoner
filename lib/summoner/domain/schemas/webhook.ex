defmodule Summoner.Domain.Schemas.Webhook do
  @moduledoc """
  Schema for webhooks (Beacons).

  A webhook binds an external HTTP trigger to an agent, pipeline, or swarm.
  Supports three auth modes (public, token, HMAC) and three response modes
  (async, sync, stream).
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Secret
  alias Summoner.Domain.Schemas.Workspace

  @target_types [:agent, :pipeline, :swarm]
  @auth_modes [:public, :token, :hmac]
  @response_modes [:sync, :async, :stream]

  schema "webhooks" do
    field :name, :string
    field :description, :string
    field :target_type, Ecto.Enum, values: @target_types
    field :target_id, Nulid.Ecto
    field :auth_mode, Ecto.Enum, values: @auth_modes
    field :transform, :string
    field :response_mode, Ecto.Enum, values: @response_modes
    field :rate_limit_rpm, :integer, default: 30
    field :timeout_s, :integer, default: 120
    field :enabled, :boolean, default: true
    field :last_triggered_at, :utc_datetime_usec
    field :trigger_count, :integer, default: 0

    belongs_to :hmac_secret, Secret
    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields ~w(name description target_type target_id auth_mode hmac_secret_id
                   transform response_mode rate_limit_rpm timeout_s enabled workspace_id)a

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :target_type, :target_id, :auth_mode, :response_mode])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:auth_mode, @auth_modes)
    |> validate_inclusion(:response_mode, @response_modes)
    |> validate_number(:rate_limit_rpm, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:timeout_s, greater_than: 0, less_than_or_equal_to: 600)
    |> validate_hmac_secret()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:hmac_secret_id)
  end

  defp validate_hmac_secret(changeset) do
    auth_mode = get_field(changeset, :auth_mode)
    hmac_secret_id = get_field(changeset, :hmac_secret_id)

    cond do
      auth_mode == :hmac and is_nil(hmac_secret_id) ->
        add_error(changeset, :hmac_secret_id, "is required when auth mode is hmac")

      auth_mode != :hmac and not is_nil(hmac_secret_id) ->
        add_error(changeset, :hmac_secret_id, "must be blank when auth mode is not hmac")

      true ->
        changeset
    end
  end
end
