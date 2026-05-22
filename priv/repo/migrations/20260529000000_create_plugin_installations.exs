defmodule Summoner.Repo.Migrations.CreatePluginInstallations do
  use Ecto.Migration

  def change do
    create table(:plugin_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :version, :string, null: false
      add :capabilities, {:array, :string}, null: false, default: []
      add :manifest, :map, null: false
      add :config, :map, null: false, default: %{}
      add :status, :string, null: false, default: "installed"
      add :error_message, :text

      add :mcp_server_id,
          references(:mcp_servers, type: :binary_id, on_delete: :nilify_all)

      add :provider_id,
          references(:providers, type: :binary_id, on_delete: :nilify_all)

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:plugin_installations, [:workspace_id])
    create unique_index(:plugin_installations, [:workspace_id, :name])

    create table(:plugin_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plugin_id,
          references(:plugin_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :external_ref, :string, null: false

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plugin_conversations, [:plugin_id, :external_ref])
    create index(:plugin_conversations, [:conversation_id])
  end
end
