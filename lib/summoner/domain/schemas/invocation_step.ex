defmodule Summoner.Domain.Schemas.InvocationStep do
  @moduledoc """
  Schema for InvocationSteps — the authoritative ReAct trace.

  One row per reasoning-action-observation cycle. Used for
  checkpoint/resume and post-hoc debugging.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Invocation

  @statuses ~w(ok error)a

  schema "invocation_steps" do
    field :step_number, :integer
    field :reasoning, :string
    field :tool_name, :string
    field :tool_input, :map
    field :tool_output, :map
    field :status, Ecto.Enum, values: @statuses

    belongs_to :invocation, Invocation

    timestamps(updated_at: false)
  end

  @required_fields ~w(invocation_id step_number)a
  @optional_fields ~w(reasoning tool_name tool_input tool_output status)a

  def changeset(step, attrs) do
    step
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:step_number, greater_than: 0)
    |> foreign_key_constraint(:invocation_id)
  end
end
