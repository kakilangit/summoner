defmodule Summoner.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workspaces, [:tenant_id])
    create unique_index(:workspaces, [:name])
  end
end
