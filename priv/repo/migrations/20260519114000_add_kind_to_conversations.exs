defmodule Summoner.Repo.Migrations.AddKindToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :kind, :string, null: false, default: "chat"
    end

    create index(:conversations, [:kind])

    flush()

    # Backfill swarm conversations
    execute(
      "UPDATE conversations SET kind = 'swarm' WHERE swarm_id IS NOT NULL",
      "UPDATE conversations SET kind = 'chat' WHERE kind = 'swarm'"
    )

    # Backfill pipeline conversations
    execute(
      "UPDATE conversations SET kind = 'pipeline' WHERE id IN (SELECT conversation_id FROM pipelines WHERE conversation_id IS NOT NULL)",
      "UPDATE conversations SET kind = 'chat' WHERE kind = 'pipeline'"
    )
  end
end
