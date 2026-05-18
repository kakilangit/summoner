defmodule Summoner.Repo.Migrations.CreatePipelineRunStages do
  use Ecto.Migration

  def change do
    create table(:pipeline_run_stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :input, :text
      add :output, :text
      add :error, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :provider_name, :string
      add :model_name, :string

      add :pipeline_run_id,
          references(:pipeline_runs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:pipeline_run_stages, [:pipeline_run_id])
  end
end
