defmodule Summoner.Conversations.Conversation do
  @moduledoc """
  Schema for Conversations — a chat thread within a workspace.

  Each conversation is owned by a user, has a primary Agent
  (the current public voice), and contains messages.

  When `swarm_id` is set, the conversation belongs to a swarm
  and uses multi-agent turn routing instead of single-agent invocation.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Accounts.User
  alias Summoner.Agents.Agent
  alias Summoner.Swarms.Swarm
  alias Summoner.Workspaces.Workspace

  schema "conversations" do
    field :title, :string
    field :kind, Ecto.Enum, values: [:chat, :swarm, :pipeline], default: :chat
    field :provider_name, :string
    field :model_name, :string

    belongs_to :workspace, Workspace
    belongs_to :primary_agent, Agent
    belongs_to :user, User
    belongs_to :swarm, Swarm

    timestamps()
  end

  @required_fields ~w(workspace_id primary_agent_id)a
  @optional_fields ~w(title kind swarm_id user_id provider_name model_name)a

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:primary_agent_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:swarm_id)
  end

  def update_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :primary_agent_id])
    |> foreign_key_constraint(:primary_agent_id)
  end
end
