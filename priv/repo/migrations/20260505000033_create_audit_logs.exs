defmodule Summoner.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :detail, :jsonb

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_logs, [:workspace_id, :inserted_at])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:agent_id])
  end
end
