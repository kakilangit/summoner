defmodule Summoner.Repo.Migrations.CreatePluginContainersAndState do
  use Ecto.Migration

  def change do
    create table(:plugin_containers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :image, :string, null: false
      add :digest, :string, null: false
      add :container_id, :string
      add :container_name, :string, null: false
      add :host, :string, null: false
      add :port, :integer, null: false, default: 9999
      add :status, :string, null: false, default: "starting"
      add :callback_token, :string, null: false
      add :active_installs, :integer, null: false, default: 0
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:plugin_containers, [:digest],
             where: "tenant_id IS NULL",
             name: :plugin_containers_shared_digest
           )

    create unique_index(:plugin_containers, [:digest, :tenant_id],
             where: "tenant_id IS NOT NULL",
             name: :plugin_containers_isolated_digest
           )

    create table(:plugin_state, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :map, null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plugin_id,
          references(:plugin_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:plugin_state, [:workspace_id, :plugin_id, :key])

    alter table(:plugin_installations) do
      add :digest, :string
      add :trusted, :boolean, default: false, null: false
    end
  end
end
