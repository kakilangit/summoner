defmodule Summoner.Orchestration.Invocation do
  @moduledoc """
  Schema for Invocations — a unit of agent work.

  Each invocation represents a single ReAct loop execution by an Agent.
  Invocations form a tree via `parent_invocation_id` for delegation,
  and link to conversations, pipelines, and rituals as trigger sources.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Conversations.Conversation
  alias Summoner.Workspaces.Workspace

  @statuses ~w(queued running completed failed handed_off awaiting_user cancelled)a
  @end_reasons ~w(
    completed failed cancelled stale handed_off
    token_limit_reached step_limit_reached total_timeout
    worker_unavailable escalation_unresolved empty_response
    doom_loop context_overflow
  )a

  schema "invocations" do
    field :depth, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :end_reason, Ecto.Enum, values: @end_reasons
    field :input, :map
    field :output, :map
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :provider_name, :string
    field :model_name, :string

    belongs_to :workspace, Workspace
    belongs_to :agent, Agent
    belongs_to :conversation, Conversation
    belongs_to :parent_invocation, {"invocations", __MODULE__}, type: Nulid.Ecto

    # Forward references — schemas defined in later phases
    field :pipeline_id, Nulid.Ecto
    field :pipeline_stage_position, :integer

    timestamps(updated_at: false)
  end

  @required_fields ~w(workspace_id agent_id)a
  @optional_fields ~w(
    conversation_id parent_invocation_id depth status
    input pipeline_id pipeline_stage_position
    provider_name model_name
  )a

  def changeset(invocation, attrs) do
    invocation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:depth, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:parent_invocation_id)
  end

  @status_fields ~w(status end_reason output started_at completed_at pipeline_stage_position)a

  def status_changeset(invocation, attrs) do
    invocation
    |> cast(attrs, @status_fields)
    |> validate_required([:status])
  end
end
