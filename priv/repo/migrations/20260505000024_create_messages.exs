defmodule Summoner.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :visibility, :string, null: false, default: "public"
      add :kind, :string, null: false, default: "chat"
      add :content, :jsonb, null: false, default: "[]"
      add :tool_call_id, :string
      add :tool_calls, :jsonb
      add :token_count, :integer
      add :deleted_at, :utc_datetime_usec
      add :compacted_at, :utc_datetime_usec
      add :thinking, :text
      add :provider_name, :string
      add :model_name, :string

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      # invocation_id FK added after invocations table is created
      add :invocation_id, :binary_id

      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:messages, [:conversation_id, :inserted_at])
    create index(:messages, [:invocation_id])
    create index(:messages, [:agent_id])
  end
end
