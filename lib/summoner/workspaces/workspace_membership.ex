defmodule Summoner.Workspaces.WorkspaceMembership do
  @moduledoc """
  Schema for workspace memberships.

  Links users to workspaces with a role that determines their permissions.

  ## Roles (highest to lowest privilege)

  - `:admin` — full control: manage workspace settings, members, roles, delete workspace, configure resources
  - `:member` — read + write: create/edit agents, conversations, pipelines, invoke agents
  - `:viewer` — read-only access to all workspace data
  """

  use Summoner.Schema

  import Ecto.Changeset

  alias Summoner.Accounts.User
  alias Summoner.Workspaces.Workspace

  @roles [:admin, :member, :viewer]

  schema "workspace_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps()
  end

  @doc "Returns the list of available roles."
  def roles, do: @roles

  @doc "Returns roles assignable by a workspace admin (excludes :admin itself)."
  def assignable_roles, do: [:member, :viewer]

  @doc """
  Changeset for creating or updating a workspace membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :workspace_id, :user_id])
    |> validate_required([:role, :workspace_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:workspace_id, :user_id])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
  end
end
