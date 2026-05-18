defmodule Summoner.Repo.Migrations.CreatePipelineRuns do
  use Ecto.Migration

  def change do
    create table(:pipeline_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "running"
      add :input, :text
      add :output, :text
      add :error, :text
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      add :pipeline_id, references(:pipelines, type: :binary_id, on_delete: :delete_all),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(updated_at: false)
    end

    create index(:pipeline_runs, [:pipeline_id])
    create index(:pipeline_runs, [:workspace_id])
  end
end
