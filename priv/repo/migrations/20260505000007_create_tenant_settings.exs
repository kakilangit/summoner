defmodule Summoner.Repo.Migrations.CreateTenantSettings do
  use Ecto.Migration

  def change do
    create table(:tenant_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :registration_mode, :string, null: false, default: "disabled"
      add :max_workspaces, :integer, null: false, default: 10
      add :max_members, :integer, null: false, default: 50
      add :token_quota_monthly, :integer
      add :budget_usd_monthly, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_settings, [:tenant_id])
  end
end
