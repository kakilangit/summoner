defmodule Summoner.Repo.Migrations.CreateA2aTasks do
  use Ecto.Migration

  def change do
    create table(:a2a_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :direction, :string, null: false
      add :context_id, :string
      add :state, :string, default: "submitted", null: false
      add :metadata, :map, default: %{}
      add :task_data, :map
      add :remote_client_info, :map
      add :a2a_server_id, references(:a2a_servers, type: :binary_id)
      add :agent_id, references(:agents, type: :binary_id)
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:a2a_tasks, [:a2a_server_id])
    create index(:a2a_tasks, [:agent_id])
    create index(:a2a_tasks, [:context_id])
  end
end
