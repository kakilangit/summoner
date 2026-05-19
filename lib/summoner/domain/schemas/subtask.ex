defmodule Summoner.Domain.Schemas.Subtask do
  @moduledoc """
  Schema for Subtasks — units of work delegated by a manager agent.

  Each subtask belongs to a manager's invocation and may be claimed by
  a worker agent. Subtasks form a DAG via `depends_on_ids`.

  ## Status Lifecycle

      pending → running (claimed + started atomically) → completed
                                                        → failed
                → pending  (requeued by reaper)
      pending → skipped (manager decision after dependency failure)
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Invocation

  @statuses ~w(pending claimed running completed failed skipped)a

  schema "subtasks" do
    field :description, :string
    field :acceptance_criteria, :string
    field :depends_on_ids, {:array, Nulid.Ecto}, default: []
    field :position, :integer
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :retry_count, :integer, default: 0

    belongs_to :invocation, Invocation
    belongs_to :worker_invocation, Invocation
    belongs_to :assigned_agent, Agent

    timestamps()
  end

  @required_fields ~w(invocation_id description position)a
  @optional_fields ~w(acceptance_criteria depends_on_ids assigned_agent_id)a

  @doc """
  Changeset for creating a new subtask.
  """
  def changeset(subtask, attrs) do
    subtask
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:invocation_id)
    |> foreign_key_constraint(:assigned_agent_id)
  end

  @claim_fields ~w(status assigned_agent_id worker_invocation_id)a

  @doc """
  Changeset for claiming a subtask (pending → running).
  """
  def claim_changeset(subtask, attrs) do
    subtask
    |> cast(attrs, @claim_fields)
    |> validate_required([:status, :assigned_agent_id, :worker_invocation_id])
    |> validate_inclusion(:status, [:running])
    |> foreign_key_constraint(:assigned_agent_id)
    |> foreign_key_constraint(:worker_invocation_id)
  end

  @status_fields ~w(status retry_count)a

  @doc """
  Changeset for status transitions (running, completed, failed, skipped).
  """
  def status_changeset(subtask, attrs) do
    subtask
    |> cast(attrs, @status_fields)
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
