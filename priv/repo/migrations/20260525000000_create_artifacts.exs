defmodule Summoner.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :content, :text
      add :content_type, :string, default: "text/markdown"
      add :version, :integer, null: false, default: 1
      add :metadata, :map, default: %{}
      add :pinned, :boolean, default: false
      add :deleted_at, :utc_datetime_usec

      add :parent_id, references(:artifacts, type: :binary_id, on_delete: :nilify_all)

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :nilify_all)

      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:workspace_id])
    create index(:artifacts, [:conversation_id])
    create index(:artifacts, [:agent_id])
    create index(:artifacts, [:parent_id])
    create index(:artifacts, [:workspace_id, :name])
  end
end
