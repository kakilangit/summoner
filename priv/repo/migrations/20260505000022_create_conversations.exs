defmodule Summoner.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :provider_name, :string
      add :model_name, :string

      add :workspace_id, references(:workspaces, type: :binary_id), null: false

      add :primary_agent_id, references(:agents, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id)
      add :swarm_id, references(:swarms, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:workspace_id])
    create index(:conversations, [:user_id])
    create index(:conversations, [:primary_agent_id])
    create index(:conversations, [:swarm_id])
  end
end
