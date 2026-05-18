defmodule Summoner.Repo.Migrations.CreateMcpServers do
  use Ecto.Migration

  def change do
    create table(:mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :transport, :string, null: false
      add :command_or_url, :text, null: false
      add :config, :map, default: %{}, null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all)
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:mcp_servers, :mcp_servers_scope_xor,
             check: "(tenant_id IS NOT NULL) != (workspace_id IS NOT NULL)"
           )

    create index(:mcp_servers, [:workspace_id])
    create index(:mcp_servers, [:tenant_id])
    create unique_index(:mcp_servers, [:workspace_id, :name], where: "workspace_id IS NOT NULL")
    create unique_index(:mcp_servers, [:tenant_id, :name], where: "tenant_id IS NOT NULL")
  end
end
