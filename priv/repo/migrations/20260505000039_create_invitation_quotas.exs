defmodule Summoner.Repo.Migrations.CreateInvitationQuotas do
  use Ecto.Migration

  def change do
    create table(:invitation_quotas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all)
      add :amount, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitation_quotas, [:user_id, :tenant_id],
             name: :invitation_quotas_user_id_tenant_id_index,
             nulls_distinct: false
           )
  end
end
