defmodule Summoner.Repo.Migrations.CreateInvocationEvents do
  use Ecto.Migration

  def change do
    create table(:invocation_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :visibility, :string, null: false, default: "public"
      add :summary, :text
      add :payload, :jsonb

      add :invocation_id, references(:invocations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:invocation_events, [:invocation_id, :inserted_at])
    create index(:invocation_events, [:agent_id])
  end
end
