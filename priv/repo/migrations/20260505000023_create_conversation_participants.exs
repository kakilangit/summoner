defmodule Summoner.Repo.Migrations.CreateConversationParticipants do
  use Ecto.Migration

  def change do
    create table(:conversation_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :joined_at, :utc_datetime_usec, null: false

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversation_participants, [:conversation_id, :agent_id])
    create index(:conversation_participants, [:agent_id])
  end
end
