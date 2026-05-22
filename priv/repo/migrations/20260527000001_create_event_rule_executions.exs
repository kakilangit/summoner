defmodule Summoner.Repo.Migrations.CreateEventRuleExecutions do
  use Ecto.Migration

  def change do
    create table(:event_rule_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "fired"
      add :event_snapshot, :map, null: false
      add :action_result, :map
      add :latency_ms, :integer
      add :error_reason, :text

      add :event_rule_id,
          references(:event_rules, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:event_rule_executions, [:event_rule_id])
    create index(:event_rule_executions, [:inserted_at])
    create index(:event_rule_executions, [:status])
  end
end
