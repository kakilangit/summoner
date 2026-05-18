defmodule Summoner.Agents.AgentLink do
  @moduledoc """
  Schema for links between Agents.

  A link connects an autonomous agent (leader) to a worker with a
  collaboration pattern (delegate or handoff). The DB columns retain
  their original names (`manager_id`, `worker_id`) for migration
  compatibility.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Agents.Agent

  @patterns ~w(delegate handoff)a

  schema "agent_links" do
    field :pattern, Ecto.Enum, values: @patterns, default: :delegate

    belongs_to :manager, Agent
    belongs_to :worker, Agent

    timestamps(updated_at: false)
  end

  @doc "All supported link patterns."
  def patterns, do: @patterns

  @doc """
  Changeset for creating an agent link.
  """
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:pattern, :manager_id, :worker_id])
    |> validate_required([:pattern, :manager_id, :worker_id])
    |> validate_not_self_link()
    |> unique_constraint([:manager_id, :worker_id])
    |> foreign_key_constraint(:manager_id)
    |> foreign_key_constraint(:worker_id)
  end

  defp validate_not_self_link(changeset) do
    manager_id = get_field(changeset, :manager_id)
    worker_id = get_field(changeset, :worker_id)

    if manager_id && worker_id && manager_id == worker_id do
      add_error(changeset, :worker_id, "cannot link an agent to itself")
    else
      changeset
    end
  end
end
