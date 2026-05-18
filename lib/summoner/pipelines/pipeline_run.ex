defmodule Summoner.Pipelines.PipelineRun do
  @moduledoc """
  Schema for pipeline runs — a single execution of a pipeline.

  Tracks overall status, input/output, timing, and has_many run stages
  for per-stage tracking.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Pipelines.{Pipeline, PipelineRunStage}

  @statuses ~w(running completed failed cancelled)a

  schema "pipeline_runs" do
    field :status, Ecto.Enum, values: @statuses, default: :running
    field :input, :string
    field :output, :string
    field :error, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :pipeline, Pipeline
    belongs_to :workspace, Summoner.Workspaces.Workspace

    has_many :stages, PipelineRunStage

    timestamps(updated_at: false)
  end

  @required_fields ~w(pipeline_id workspace_id started_at)a
  @optional_fields ~w(status input output error completed_at)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:workspace_id)
  end
end
