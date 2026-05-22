defmodule Summoner.Repo.Migrations.CreateAgentMemories do
  use Ecto.Migration

  def change do
    create table(:agent_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :confidence, :float, null: false, default: 1.0
      add :last_accessed_at, :utc_datetime_usec, null: false
      add :access_count, :integer, null: false, default: 0

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :source_conversation_id,
          references(:conversations, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_memories, [:agent_id])
    create index(:agent_memories, [:workspace_id])
    create index(:agent_memories, [:agent_id, :type])
    create index(:agent_memories, [:confidence])
    create index(:agent_memories, [:last_accessed_at])

    execute(
      "CREATE INDEX agent_memories_embedding_index ON agent_memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX agent_memories_embedding_index"
    )
  end
end
