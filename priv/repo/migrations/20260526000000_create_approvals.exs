defmodule Summoner.Repo.Migrations.CreateApprovals do
  use Ecto.Migration

  def change do
    create table(:approval_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :trigger_type, :string, null: false
      add :trigger_config, :map, null: false, default: %{}
      add :approver_roles, {:array, :string}, default: ["admin"]
      add :timeout_s, :integer, default: 3600
      add :timeout_action, :string, default: "reject"
      add :enabled, :boolean, default: true

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:approval_rules, [:workspace_id])

    create table(:pending_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"

      add :rule_id,
          references(:approval_rules, type: :binary_id, on_delete: :delete_all),
          null: false

      add :invocation_id,
          references(:invocations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :agent_id,
          references(:agents, type: :binary_id, on_delete: :delete_all),
          null: false

      add :action_summary, :string, null: false
      add :action_details, :map, null: false, default: %{}
      add :decided_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :decision_note, :string

      add :workspace_id,
          references(:workspaces, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:pending_approvals, [:workspace_id])
    create index(:pending_approvals, [:invocation_id])
    create index(:pending_approvals, [:status])

    # Add approval-related status to invocations
    # The invocation can be paused awaiting approval
    alter table(:invocations) do
      add :paused_at, :utc_datetime_usec
      add :paused_tool_call, :map
    end
  end
end
