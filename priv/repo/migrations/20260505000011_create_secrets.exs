defmodule Summoner.Repo.Migrations.CreateSecrets do
  use Ecto.Migration

  def change do
    create table(:secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :encrypted_value, :binary, null: false
      add :description, :string

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create constraint(:secrets, :secrets_scope_xor,
             check: "(tenant_id IS NOT NULL) != (workspace_id IS NOT NULL)"
           )

    create unique_index(:secrets, [:workspace_id, :name], where: "workspace_id IS NOT NULL")
    create unique_index(:secrets, [:tenant_id, :name], where: "tenant_id IS NOT NULL")
    create index(:secrets, [:workspace_id])
    create index(:secrets, [:tenant_id])
  end
end
