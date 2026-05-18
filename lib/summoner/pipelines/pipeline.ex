defmodule Summoner.Pipelines.Pipeline do
  @moduledoc """
  Schema for Pipelines — sequential or orchestrated chains of agents.

  ## Modes

  - `:simple` — stages run sequentially; each stage's output feeds the next
  - `:orchestrated` — a designated manager agent receives the pipeline
    definition as a subtask plan and uses its delegation system to execute

  ## Trigger types

  - `:manual` — user triggers via the UI
  - `:scheduled` — Oban cron checks `cron_expression` each minute
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent
  alias Summoner.Conversations.Conversation
  alias Summoner.Pipelines.PipelineStage
  alias Summoner.Workspaces.Workspace

  schema "pipelines" do
    field :name, :string
    field :mode, Ecto.Enum, values: [:simple, :orchestrated], default: :simple
    field :trigger_type, Ecto.Enum, values: [:manual, :scheduled], default: :manual
    field :cron_expression, :string

    belongs_to :workspace, Workspace
    belongs_to :orchestrator_agent, Agent
    belongs_to :conversation, Conversation
    has_many :stages, PipelineStage, preload_order: [asc: :position]

    timestamps()
  end

  @required_fields ~w(name workspace_id)a
  @optional_fields ~w(mode trigger_type cron_expression orchestrator_agent_id conversation_id)a

  @cron_regex ~r/^([0-9,\-\/\*]+)\s+([0-9,\-\/\*]+)\s+([0-9,\-\/\*]+)\s+([0-9,\-\/\*]+)\s+([0-9,\-\/\*]+)$/

  def changeset(pipeline, attrs) do
    pipeline
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_cron_expression()
    |> validate_orchestrator()
    |> unique_constraint([:workspace_id, :name],
      message: "pipeline name already exists in this sanctum"
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:orchestrator_agent_id)
  end

  defp validate_cron_expression(changeset) do
    trigger = get_field(changeset, :trigger_type)
    cron = get_field(changeset, :cron_expression)

    cond do
      trigger == :scheduled && (is_nil(cron) || cron == "") ->
        add_error(changeset, :cron_expression, "is required for scheduled pipelines")

      trigger == :scheduled && !Regex.match?(@cron_regex, cron) ->
        add_error(changeset, :cron_expression, "must be a valid 5-field cron expression")

      true ->
        changeset
    end
  end

  defp validate_orchestrator(changeset) do
    mode = get_field(changeset, :mode)
    orchestrator_id = get_field(changeset, :orchestrator_agent_id)

    if mode == :orchestrated && is_nil(orchestrator_id) do
      add_error(changeset, :orchestrator_agent_id, "is required for orchestrated pipelines")
    else
      changeset
    end
  end

  def modes, do: [:simple, :orchestrated]
  def trigger_types, do: [:manual, :scheduled]
end
