defmodule Summoner.Repo.Migrations.RenameA2aTokensToAccessTokens do
  use Ecto.Migration

  def up do
    rename table(:a2a_tokens), to: table(:access_tokens)

    alter table(:access_tokens) do
      add :scopes, {:array, :string}, null: false, default: []
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)
      add :expires_at, :utc_datetime_usec
      add :rate_limit_rpm, :integer, null: false, default: 100
    end

    flush()

    execute(
      "UPDATE access_tokens SET tenant_id = w.tenant_id FROM workspaces w WHERE access_tokens.workspace_id = w.id"
    )

    alter table(:access_tokens) do
      modify :tenant_id, :binary_id, null: false
    end

    create index(:access_tokens, [:user_id])
    create index(:access_tokens, [:tenant_id])
    create index(:access_tokens, [:expires_at])
  end

  def down do
    drop_if_exists index(:access_tokens, [:expires_at])
    drop_if_exists index(:access_tokens, [:tenant_id])
    drop_if_exists index(:access_tokens, [:user_id])

    alter table(:access_tokens) do
      remove :rate_limit_rpm
      remove :expires_at
      remove_if_exists :tenant_id, :binary_id
      remove :user_id
      remove :scopes
    end

    rename table(:access_tokens), to: table(:a2a_tokens)
  end
end
