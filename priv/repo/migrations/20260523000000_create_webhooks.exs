defmodule Summoner.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false
      add :auth_mode, :string, null: false, default: "token"
      add :hmac_secret_id, references(:secrets, type: :binary_id, on_delete: :nilify_all)
      add :transform, :text
      add :response_mode, :string, null: false, default: "async"
      add :rate_limit_rpm, :integer, default: 30
      add :timeout_s, :integer, default: 120
      add :enabled, :boolean, default: true
      add :last_triggered_at, :utc_datetime_usec
      add :trigger_count, :integer, default: 0

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhooks, [:workspace_id])
    create index(:webhooks, [:target_type, :target_id])
  end
end
