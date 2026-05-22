defmodule Summoner.Repo.Migrations.CreateKnowledgeBases do
  use Ecto.Migration

  def change do
    create table(:knowledge_bases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :config, :map, null: false, default: %{}
      add :embedding_model, :string, null: false, default: "text-embedding-3-small"
      add :chunk_strategy, :string, null: false, default: "fixed"
      add :chunk_size, :integer, null: false, default: 512
      add :chunk_overlap, :integer, null: false, default: 64
      add :status, :string, null: false, default: "pending"
      add :document_count, :integer, null: false, default: 0
      add :error_message, :text
      add :file_hashes, :map, null: false, default: %{}

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:knowledge_bases, [:workspace_id])
    create unique_index(:knowledge_bases, [:workspace_id, :name])

    create table(:knowledge_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :metadata, :map, null: false, default: %{}
      add :document_name, :string, null: false

      add :knowledge_base_id,
          references(:knowledge_bases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:knowledge_chunks, [:knowledge_base_id])
    create index(:knowledge_chunks, [:workspace_id])
    create index(:knowledge_chunks, [:knowledge_base_id, :document_name])

    execute(
      "CREATE INDEX knowledge_chunks_embedding_idx ON knowledge_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 200)",
      "DROP INDEX knowledge_chunks_embedding_idx"
    )

    create table(:knowledge_base_agents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_base_id,
          references(:knowledge_bases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :agent_id,
          references(:agents, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:knowledge_base_agents, [:knowledge_base_id, :agent_id])
    create index(:knowledge_base_agents, [:agent_id])
  end
end
