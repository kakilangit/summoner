defmodule Summoner.Domain.Schemas.PipelineRunStage do
  @moduledoc """
  Schema for pipeline run stages — per-stage execution tracking.

  Records input, output, status, and timing for each stage in a run.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.PipelineRun

  @statuses ~w(pending running completed failed skipped)a

  schema "pipeline_run_stages" do
    field :position, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :input, :string
    field :output, :string
    field :error, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :provider_name, :string
    field :model_name, :string

    belongs_to :pipeline_run, PipelineRun
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(position pipeline_run_id)a
  @optional_fields ~w(agent_id status input output error started_at completed_at provider_name model_name)a

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:pipeline_run_id)
    |> foreign_key_constraint(:agent_id)
  end
end
