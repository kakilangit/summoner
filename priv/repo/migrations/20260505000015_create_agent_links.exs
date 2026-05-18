defmodule Summoner.Repo.Migrations.CreateAgentLinks do
  use Ecto.Migration

  def change do
    create table(:agent_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :manager_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :worker_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :pattern, :string, null: false, default: "delegate"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:agent_links, [:manager_id])
    create index(:agent_links, [:worker_id])
    create unique_index(:agent_links, [:manager_id, :worker_id])
  end
end
