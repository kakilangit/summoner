defmodule Summoner.Repo.Migrations.CreateSwarms do
  use Ecto.Migration

  def change do
    create table(:swarms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :mode, :string, null: false, default: "relay"
      add :max_turns, :integer, null: false, default: 20

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      add :coordinator_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:swarms, [:workspace_id, :name])
    create index(:swarms, [:coordinator_agent_id])
  end
end
