defmodule Summoner.Repo.Migrations.CreateTokenUsages do
  use Ecto.Migration

  def change do
    create table(:token_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :prompt_tokens, :integer, null: false, default: 0
      add :completion_tokens, :integer, null: false, default: 0
      add :total_tokens, :integer, null: false, default: 0
      add :model, :string, null: false
      add :estimated, :boolean, null: false, default: false
      add :cost_usd, :decimal, precision: 12, scale: 6

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invocation_id, references(:invocations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:token_usages, [:workspace_id])
    create index(:token_usages, [:agent_id])
    create index(:token_usages, [:provider_id])
    create index(:token_usages, [:invocation_id])
    create index(:token_usages, [:inserted_at])
  end
end
