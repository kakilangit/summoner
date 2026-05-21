defmodule Summoner.Domain.Schemas.AgentFailoverEntry do
  @moduledoc """
  Schema for an entry in an agent's failover chain.

  Each agent can have an ordered list of backup agents. When the primary
  fails with a failover-eligible error, backups are tried in position order.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent

  schema "agent_failover_chain" do
    field :position, :integer

    belongs_to :agent, Agent
    belongs_to :backup_agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(agent_id backup_agent_id position)a

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_not_self_backup()
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:backup_agent_id)
    |> unique_constraint([:agent_id, :backup_agent_id],
      name: :agent_failover_chain_agent_id_backup_agent_id_index,
      message: "already in failover chain"
    )
  end

  defp validate_not_self_backup(changeset) do
    agent_id = get_field(changeset, :agent_id)
    backup_id = get_field(changeset, :backup_agent_id)

    if agent_id && backup_id && agent_id == backup_id do
      add_error(changeset, :backup_agent_id, "cannot back up itself")
    else
      changeset
    end
  end
end
