defmodule Summoner.Repo.Migrations.CreatePipelines do
  use Ecto.Migration

  def change do
    create table(:pipelines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :mode, :string, null: false, default: "simple"
      add :trigger_type, :string, null: false, default: "manual"
      add :cron_expression, :string

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :orchestrator_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:pipelines, [:workspace_id])
    create unique_index(:pipelines, [:workspace_id, :name])
    create index(:pipelines, [:conversation_id])
  end
end
