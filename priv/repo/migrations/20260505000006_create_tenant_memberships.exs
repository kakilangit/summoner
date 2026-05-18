defmodule Summoner.Repo.Migrations.CreateTenantMemberships do
  use Ecto.Migration

  def change do
    create table(:tenant_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tenant_memberships, [:tenant_id])
    create index(:tenant_memberships, [:user_id])
    create unique_index(:tenant_memberships, [:tenant_id, :user_id])
  end
end
