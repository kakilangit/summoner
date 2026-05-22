defmodule Summoner.Domain.Schemas.PluginConversation do
  @moduledoc """
  Maps a plugin's external reference (e.g. Slack channel:timestamp) to a
  Summoner conversation.

  When forwarding events via `summoner/event`, Summoner enriches with
  `external_ref` so the plugin knows which external thread the event
  relates to.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.{Conversation, PluginInstallation}

  schema "plugin_conversations" do
    field :external_ref, :string

    belongs_to :plugin, PluginInstallation
    belongs_to :conversation, Conversation

    timestamps()
  end

  def changeset(plugin_conversation, attrs) do
    plugin_conversation
    |> cast(attrs, [:external_ref, :plugin_id, :conversation_id])
    |> validate_required([:external_ref, :plugin_id, :conversation_id])
    |> foreign_key_constraint(:plugin_id)
    |> foreign_key_constraint(:conversation_id)
    |> unique_constraint([:plugin_id, :external_ref])
  end
end
