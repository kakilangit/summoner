defmodule Summoner.Repo.Migrations.CreateMediaAttachments do
  use Ecto.Migration

  def change do
    create table(:media_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)

      add :source, :string, null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :file_size, :integer
      add :width, :integer
      add :height, :integer
      add :duration_s, :float
      add :prompt, :text
      add :revised_prompt, :text
      add :model_name, :string
      add :provider_name, :string
      add :error, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:media_attachments, [:workspace_id])
    create index(:media_attachments, [:conversation_id])
    create index(:media_attachments, [:message_id])
    create index(:media_attachments, [:workspace_id, :status])
    create index(:media_attachments, [:workspace_id, :type])
  end
end
