defmodule Summoner.Repo.Migrations.CreateMediaProviders do
  use Ecto.Migration

  def change do
    create table(:media_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all)

      add :name, :string, null: false
      add :default_image_model, :string
      add :default_video_model, :string
      add :max_concurrent_jobs, :integer, default: 3
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:media_providers, :media_providers_scope_xor,
             check: "(tenant_id IS NOT NULL) != (workspace_id IS NOT NULL)"
           )

    create unique_index(:media_providers, [:workspace_id, :name],
             where: "workspace_id IS NOT NULL"
           )

    create unique_index(:media_providers, [:tenant_id, :name], where: "tenant_id IS NOT NULL")
    create index(:media_providers, [:workspace_id])
    create index(:media_providers, [:tenant_id])
    create index(:media_providers, [:provider_id])

    # Add media_provider_id FK to agents (deferred from agents creation)
    alter table(:agents) do
      add :media_provider_id,
          references(:media_providers, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:agents, [:media_provider_id])
  end
end
