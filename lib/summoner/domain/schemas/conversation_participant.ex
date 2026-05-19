defmodule Summoner.Domain.Schemas.ConversationParticipant do
  @moduledoc """
  Schema for tracking which Agents have participated in a conversation.

  This is a membership log — the current primary voice is always
  `conversations.primary_agent_id`, not derived from this table.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Agent
  alias Summoner.Domain.Schemas.Conversation

  schema "conversation_participants" do
    field :joined_at, :utc_datetime_usec

    belongs_to :conversation, Conversation
    belongs_to :agent, Agent

    timestamps()
  end

  @required_fields ~w(conversation_id agent_id)a

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint([:conversation_id, :agent_id])
    |> put_joined_at()
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
    end
  end
end
