defmodule Summoner.Repo.Migrations.CreateA2aServers do
  use Ecto.Migration

  def change do
    create table(:a2a_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :enabled, :boolean, default: true, null: false
      add :access_mode, :string, default: "public", null: false
      add :allowed_skills, {:array, :string}, default: [], null: false
      add :agent_id, references(:agents, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:a2a_servers, [:agent_id])
  end
end
