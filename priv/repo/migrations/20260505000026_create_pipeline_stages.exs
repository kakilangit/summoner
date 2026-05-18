defmodule Summoner.Repo.Migrations.CreatePipelineStages do
  use Ecto.Migration

  def change do
    create table(:pipeline_stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position, :integer, null: false
      add :instruction, :text
      add :depends_on_positions, {:array, :integer}, default: []

      add :pipeline_id, references(:pipelines, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :restrict), null: false

      timestamps(updated_at: false)
    end

    create index(:pipeline_stages, [:pipeline_id])
    create unique_index(:pipeline_stages, [:pipeline_id, :position])
  end
end
