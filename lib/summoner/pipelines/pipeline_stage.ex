defmodule Summoner.Pipelines.PipelineStage do
  @moduledoc """
  Schema for PipelineStages — individual steps in a pipeline.

  Each stage references an agent, has a position (0-indexed), and
  an instruction that tells the agent what to do at this step.
  The instruction is combined with the previous stage's output
  to form the agent's input message.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Pipelines.Pipeline

  schema "pipeline_stages" do
    field :position, :integer
    field :instruction, :string
    field :depends_on_positions, {:array, :integer}, default: []

    belongs_to :pipeline, Pipeline
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(position pipeline_id agent_id)a
  @optional_fields ~w(instruction depends_on_positions)a

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:pipeline_id, :position],
      message: "position already taken in this pipeline"
    )
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:agent_id)
  end
end
