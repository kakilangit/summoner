defmodule Summoner.Repo.Migrations.CreateAgentSkills do
  use Ecto.Migration

  def change do
    create table(:agent_skills, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_id, references(:agents, type: :binary_id, on_delete: :restrict), null: false
      add :skill_id, references(:skills, type: :binary_id, on_delete: :restrict), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:agent_skills, [:agent_id, :skill_id])
    create index(:agent_skills, [:skill_id])
  end
end
