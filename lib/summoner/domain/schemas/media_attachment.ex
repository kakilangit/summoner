defmodule Summoner.Domain.Schemas.MediaAttachment do
  @moduledoc """
  Schema for media attachments (Artifacts).

  Tracks images and videos — both user-uploaded (Offered) and
  AI-generated (Forged). Lifecycle states:

  - `pending` (Standing By) — generation in progress
  - `ready` (Ready) — file stored and available
  - `failed` (Failed) — generation or upload failed
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.{Conversation, Message}
  alias Summoner.Domain.Schemas.Workspace

  @sources ~w(generated uploaded)a
  @types ~w(image video)a
  @statuses ~w(pending ready failed)a

  @max_filename_length 255

  schema "media_attachments" do
    field :source, Ecto.Enum, values: @sources
    field :type, Ecto.Enum, values: @types
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :width, :integer
    field :height, :integer
    field :duration_s, :float
    field :prompt, :string
    field :revised_prompt, :string
    field :model_name, :string
    field :provider_name, :string
    field :error, :string
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :conversation, Conversation
    belongs_to :message, Message

    timestamps()
  end

  @required_fields ~w(workspace_id conversation_id source type filename content_type)a
  @optional_fields ~w(message_id status file_size width height duration_s prompt revised_prompt model_name provider_name error metadata)a

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:filename, max: @max_filename_length)
    |> validate_number(:file_size, greater_than: 0)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:message_id)
  end

  @doc """
  Changeset for marking an attachment as ready after successful storage.
  """
  def ready_changeset(attachment, attrs) do
    attachment
    |> cast(attrs, ~w(file_size width height duration_s revised_prompt message_id)a)
    |> put_change(:status, :ready)
  end

  @doc """
  Changeset for marking an attachment as failed.
  """
  def failed_changeset(attachment, reason) do
    attachment
    |> change(status: :failed, error: reason)
  end
end
