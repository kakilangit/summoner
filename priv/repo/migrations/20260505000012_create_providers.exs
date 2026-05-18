defmodule Summoner.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      add :name, :string, null: false
      add :kind, :string, null: false
      add :api_format, :string, null: false
      add :type, :string, null: false
      add :base_url, :string, null: false
      add :status, :string, null: false, default: "unknown"
      add :cached_models, {:array, :string}, null: false, default: []

      add :api_key_secret_id, references(:secrets, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:providers, :providers_scope_xor,
             check: "(tenant_id IS NOT NULL) != (workspace_id IS NOT NULL)"
           )

    create index(:providers, [:workspace_id])
    create index(:providers, [:tenant_id])
    create unique_index(:providers, [:workspace_id, :name], where: "workspace_id IS NOT NULL")
    create unique_index(:providers, [:tenant_id, :name], where: "tenant_id IS NOT NULL")
    create index(:providers, [:api_key_secret_id])
  end
end
