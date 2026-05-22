defmodule Summoner.Domain.Schemas.EventRule do
  @moduledoc """
  Schema for event rules (Omens).

  Declarative rules that subscribe to internal domain events and trigger
  actions when configurable conditions are met. Turns Summoner from a
  request-driven platform into a reactive one.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Workspace

  @event_types ~w(
    invocation.started invocation.completed invocation.failed
    pipeline.started pipeline.completed pipeline.failed
    swarm.turn swarm.done swarm.timeout
    conversation.message
    webhook.triggered webhook.failed
    failover
    approval.pending approval.approved approval.rejected approval.expired
    media.started media.completed media.failed
    copilot.connected copilot.failed
    agent.config_changed
  )

  @action_types [:invoke_agent, :run_pipeline, :call_webhook, :send_notification]

  schema "event_rules" do
    field :name, :string
    field :description, :string
    field :event_type, :string
    field :conditions, :map, default: %{}
    field :action_type, Ecto.Enum, values: @action_types
    field :action_config, :map, default: %{}
    field :cooldown_s, :integer, default: 0
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 100
    field :last_fired_at, :utc_datetime_usec
    field :fire_count, :integer, default: 0
    field :consecutive_failures, :integer, default: 0
    field :disabled_until, :utc_datetime_usec
    field :max_fires_per_hour, :integer, default: 0

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields ~w(name description event_type conditions action_type action_config
                   cooldown_s enabled priority workspace_id max_fires_per_hour)a

  def changeset(event_rule, attrs) do
    event_rule
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :event_type, :action_type, :action_config])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:action_type, @action_types)
    |> validate_number(:cooldown_s, greater_than_or_equal_to: 0, less_than_or_equal_to: 86_400)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:max_fires_per_hour,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000
    )
    |> validate_action_config()
    |> unique_constraint([:workspace_id, :name])
    |> foreign_key_constraint(:workspace_id)
  end

  def event_types, do: @event_types

  defp validate_action_config(changeset) do
    action_type = get_field(changeset, :action_type)
    action_config = get_field(changeset, :action_config) || %{}

    case action_type do
      :invoke_agent ->
        if is_nil(action_config["agent_id"]) and is_nil(action_config["agent_callname"]),
          do: add_error(changeset, :action_config, "requires agent_id or agent_callname"),
          else: changeset

      :run_pipeline ->
        if is_nil(action_config["pipeline_id"]),
          do: add_error(changeset, :action_config, "requires pipeline_id"),
          else: changeset

      :call_webhook ->
        if is_nil(action_config["url"]),
          do: add_error(changeset, :action_config, "requires url"),
          else: changeset

      :send_notification ->
        changeset

      _ ->
        changeset
    end
  end
end
