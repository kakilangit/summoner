defmodule Summoner.Repo.Migrations.AddHardeningToEventRules do
  use Ecto.Migration

  def change do
    alter table(:event_rules) do
      add :consecutive_failures, :integer, null: false, default: 0
      add :disabled_until, :utc_datetime_usec
      add :max_fires_per_hour, :integer, null: false, default: 0
    end
  end
end
