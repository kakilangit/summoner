defmodule Summoner.Repo.Migrations.AddBackupAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :failover_strategy, :string, default: "auto"
      add :failover_delay_ms, :integer, default: 0
      add :max_failover_depth, :integer, default: 3
    end

    create table(:agent_failover_chain, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :backup_agent_id, references(:agents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false

      timestamps(updated_at: false)
    end

    create index(:agent_failover_chain, [:agent_id, :position])
    create unique_index(:agent_failover_chain, [:agent_id, :backup_agent_id])

    alter table(:invocations) do
      add :failover_from_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :failover_reason, :string
      add :failover_depth, :integer, default: 0
    end
  end
end
