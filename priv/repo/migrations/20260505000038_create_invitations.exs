defmodule Summoner.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :code, :string, null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)

      add :invited_by_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :used_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitations, [:code])
    create index(:invitations, [:tenant_id])
    create index(:invitations, [:invited_by_id])
    create index(:invitations, [:used_by_id])
  end
end
