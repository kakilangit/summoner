defmodule Summoner.Repo.Migrations.CreateSwarmMembers do
  use Ecto.Migration

  def change do
    create table(:swarm_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false, default: 0

      add :swarm_id,
          references(:swarms, type: :binary_id, on_delete: :delete_all),
          null: false

      add :agent_id,
          references(:agents, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(updated_at: false)
    end

    create unique_index(:swarm_members, [:swarm_id, :agent_id])
    create index(:swarm_members, [:agent_id])
    create index(:swarm_members, [:swarm_id, :position])
  end
end
