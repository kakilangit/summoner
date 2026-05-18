defmodule Summoner.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider_id, references(:providers, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :callname, :string
      add :system_prompt, :text
      add :personality, :text
      add :model, :string, null: false
      add :role, :string, null: false, default: "autonomous"
      add :max_steps, :integer, null: false, default: 10
      add :max_concurrent_invocations, :integer, null: false, default: 1
      add :max_delegation_concurrency, :integer, null: false, default: 3
      add :max_tokens_per_invocation, :integer, null: false, default: 50_000
      add :context_length, :integer
      add :step_timeout_s, :integer, null: false, default: 60
      add :total_timeout_s, :integer, null: false, default: 300
      add :stream_tokens_to_observability, :boolean, null: false, default: false
      add :budget_usd, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agents, [:workspace_id])
    create index(:agents, [:provider_id])
    create unique_index(:agents, [:workspace_id, :callname])
  end
end
