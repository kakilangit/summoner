defmodule Summoner.Domain.Schemas.Workspace do
  @moduledoc """
  Schema for workspaces — the primary isolation boundary.

  Each workspace owns its own set of Agents, Skills, MCP servers,
  Quests, and Providers. Users belong to workspaces via memberships.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.Tenant
  alias Summoner.Domain.Schemas.{WorkspaceMembership, WorkspaceSettings}

  schema "workspaces" do
    field :name, :string

    belongs_to :tenant, Tenant
    has_many :memberships, WorkspaceMembership
    has_one :settings, WorkspaceSettings

    timestamps()
  end

  @doc """
  Changeset for creating or updating a workspace.
  """
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :tenant_id])
    |> validate_required([:name, :tenant_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:name)
  end
end
