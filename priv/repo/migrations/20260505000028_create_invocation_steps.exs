defmodule Summoner.Repo.Migrations.CreateInvocationSteps do
  use Ecto.Migration

  def change do
    create table(:invocation_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_number, :integer, null: false
      add :reasoning, :text
      add :tool_name, :string
      add :tool_input, :jsonb
      add :tool_output, :jsonb
      add :status, :string

      add :invocation_id, references(:invocations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:invocation_steps, [:invocation_id, :step_number])
  end
end
