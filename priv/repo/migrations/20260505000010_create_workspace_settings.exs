defmodule Summoner.Repo.Migrations.CreateWorkspaceSettings do
  use Ecto.Migration

  def change do
    create table(:workspace_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :context_window_messages, :integer, null: false, default: 20
      add :max_tool_output_chars, :integer, default: 32_000
      add :token_quota_monthly, :integer
      add :budget_usd_monthly, :decimal, precision: 10, scale: 2
      add :harness, :text
      add :default_step_timeout_s, :integer, default: 60, null: false
      add :default_total_timeout_s, :integer, default: 300, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspace_settings, [:workspace_id])
  end
end
