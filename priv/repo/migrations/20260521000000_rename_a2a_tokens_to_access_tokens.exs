defmodule Summoner.Repo.Migrations.RenameA2aTokensToAccessTokens do
  use Ecto.Migration

  def change do
    rename table(:a2a_tokens), to: table(:access_tokens)

    alter table(:access_tokens) do
      add :scopes, {:array, :string}, null: false, default: []
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :expires_at, :utc_datetime_usec
      add :rate_limit_rpm, :integer, null: false, default: 100
    end

    create index(:access_tokens, [:user_id])
    create index(:access_tokens, [:expires_at])
  end
end
