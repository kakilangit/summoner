defmodule Summoner.Domain.Schemas.InvocationEvent do
  @moduledoc """
  Schema for InvocationEvents — the notification/PubSub layer.

  Lightweight event records that drive UI updates via PubSub.
  Written in parallel with invocation steps.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Invocation

  @event_types ~w(
    planning_started subtask_created subtask_claimed subtask_completed
    tool_started tool_finished tool_failed
    handoff_started handoff_completed
    pipeline_stage_started pipeline_stage_completed
    awaiting_user token_limit_reached
    completed failed reaper
  )a

  @visibilities ~w(public internal)a

  schema "invocation_events" do
    field :event_type, Ecto.Enum, values: @event_types
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :summary, :string
    field :payload, :map

    belongs_to :invocation, Invocation
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(invocation_id event_type)a
  @optional_fields ~w(agent_id visibility summary payload)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:invocation_id)
    |> foreign_key_constraint(:agent_id)
  end
end
