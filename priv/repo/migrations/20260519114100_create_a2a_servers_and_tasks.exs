defmodule Summoner.Repo.Migrations.CreateA2aServersAndTasks do
  use Ecto.Migration

  def change do
    create table(:a2a_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :enabled, :boolean, default: true, null: false
      add :auth_mode, :string, default: "none", null: false
      add :api_key_hash, :string
      add :rate_limit_rpm, :integer, default: 60, null: false
      add :allowed_skills, {:array, :string}, default: [], null: false
      add :agent_id, references(:agents, type: :binary_id), null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:a2a_servers, [:agent_id])

    create table(:a2a_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :direction, :string, null: false
      add :context_id, :string
      add :state, :string, default: "submitted", null: false
      add :metadata, :map, default: %{}
      add :remote_client_info, :map
      add :a2a_server_id, references(:a2a_servers, type: :binary_id)
      add :agent_id, references(:agents, type: :binary_id)
      add :conversation_id, references(:conversations, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:a2a_tasks, [:a2a_server_id])
    create index(:a2a_tasks, [:agent_id])
    create index(:a2a_tasks, [:context_id])
  end
end
