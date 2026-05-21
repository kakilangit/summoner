defmodule Summoner.Domain.Schemas.EventRuleExecution do
  @moduledoc """
  Schema for event rule execution records.

  Audit trail for every time an event rule fires. Tracks the triggering
  event snapshot, action result, latency, and any errors.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.EventRule

  @statuses [:fired, :succeeded, :failed]

  schema "event_rule_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :fired
    field :event_snapshot, :map
    field :action_result, :map
    field :latency_ms, :integer
    field :error_reason, :string

    belongs_to :event_rule, EventRule

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @cast_fields ~w(status event_snapshot action_result latency_ms error_reason event_rule_id)a

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @cast_fields)
    |> validate_required([:status, :event_snapshot, :event_rule_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:event_rule_id)
  end
end
