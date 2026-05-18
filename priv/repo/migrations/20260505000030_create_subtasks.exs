defmodule Summoner.Repo.Migrations.CreateSubtasks do
  use Ecto.Migration

  def change do
    create table(:subtasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :invocation_id,
          references(:invocations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :worker_invocation_id,
          references(:invocations, type: :binary_id, on_delete: :nilify_all)

      add :assigned_agent_id,
          references(:agents, type: :binary_id, on_delete: :nilify_all)

      add :description, :text, null: false
      add :acceptance_criteria, :text
      add :depends_on_ids, {:array, :binary}, default: []
      add :position, :integer, null: false
      add :status, :string, null: false, default: "pending"
      add :retry_count, :integer, null: false, default: 0

      timestamps()
    end

    create index(:subtasks, [:invocation_id])
    create index(:subtasks, [:worker_invocation_id])
    create index(:subtasks, [:assigned_agent_id])
    create index(:subtasks, [:invocation_id, :status])
  end
end
