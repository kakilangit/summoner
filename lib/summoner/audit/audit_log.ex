defmodule Summoner.Audit.AuditLog do
  @moduledoc """
  Schema for AuditLog — compliance and observability records.

  Tracks significant actions across the system: quota events,
  invocation lifecycle, git operations, etc. Each entry is
  workspace-scoped and optionally linked to a user and/or agent.
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Accounts.User
  alias Summoner.Agents.Agent
  alias Summoner.Workspaces.Workspace

  schema "audit_logs" do
    field :action, :string
    field :detail, :map

    belongs_to :workspace, Workspace
    belongs_to :user, User
    belongs_to :agent, Agent

    timestamps(updated_at: false)
  end

  @required_fields ~w(workspace_id action)a
  @optional_fields ~w(user_id agent_id detail)a

  def changeset(log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:action, min: 1, max: 255)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:agent_id)
  end
end
