defmodule Summoner.Repo.Migrations.CreateA2aTokens do
  use Ecto.Migration

  def change do
    create table(:a2a_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :token_hash, :string, null: false
      add :last_used_at, :utc_datetime_usec
      add :request_count, :integer, null: false, default: 0
      add :revoked_at, :utc_datetime_usec

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:a2a_tokens, [:workspace_id])
    create index(:a2a_tokens, [:token_hash], unique: true)
  end
end
