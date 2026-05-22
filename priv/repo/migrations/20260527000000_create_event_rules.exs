defmodule Summoner.Repo.Migrations.CreateEventRules do
  use Ecto.Migration

  def change do
    create table(:event_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :event_type, :string, null: false
      add :conditions, :map, null: false, default: %{}
      add :action_type, :string, null: false
      add :action_config, :map, null: false, default: %{}
      add :cooldown_s, :integer, null: false, default: 0
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 100
      add :last_fired_at, :utc_datetime_usec
      add :fire_count, :integer, null: false, default: 0

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_rules, [:workspace_id, :event_type])
    create index(:event_rules, [:workspace_id, :enabled])
    create unique_index(:event_rules, [:workspace_id, :name])
  end
end
