defmodule Summoner.Repo.Migrations.CreateAgentMcpServers do
  use Ecto.Migration

  def change do
    create table(:agent_mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :mcp_server_id, references(:mcp_servers, type: :binary_id, on_delete: :restrict),
        null: false

      add :env, :map, default: %{}, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_mcp_servers, [:agent_id, :mcp_server_id])
    create index(:agent_mcp_servers, [:mcp_server_id])
  end
end
