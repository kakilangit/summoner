defmodule Summoner.Repo.Migrations.CreateInvocations do
  use Ecto.Migration

  def change do
    create table(:invocations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :depth, :integer, null: false, default: 0
      add :status, :string, null: false, default: "queued"
      add :end_reason, :string
      add :input, :jsonb
      add :output, :jsonb
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :provider_name, :string
      add :model_name, :string

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :nilify_all)

      add :parent_invocation_id,
          references(:invocations, type: :binary_id, on_delete: :nilify_all)

      add :pipeline_id, :binary_id
      add :pipeline_stage_position, :integer

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:invocations, [:workspace_id])
    create index(:invocations, [:agent_id])
    create index(:invocations, [:conversation_id])
    create index(:invocations, [:parent_invocation_id])
    create index(:invocations, [:status])

    create index(:invocations, [:agent_id, :status, :inserted_at],
             name: :invocations_agent_status_inserted_idx
           )

    # Add deferred FK from messages -> invocations
    alter table(:messages) do
      modify :invocation_id, references(:invocations, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end
  end
end
