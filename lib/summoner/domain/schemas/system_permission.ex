defmodule Summoner.Domain.Schemas.SystemPermission do
  @moduledoc """
  Schema for system-level permissions granted to specific users.

  Only root admin (configured via ROOT_ADMIN_EMAIL env var) can grant
  system permissions. These permissions control system-wide operations
  that span across all tenants and workspaces.

  ## Permissions

  - `:manage_users` - Create, update, disable users; manage user roles
  - `:manage_tenants` - Create, update, disable tenants
  - `:manage_system_settings` - Modify system-wide configuration
  - `:view_system_stats` - View system-wide statistics and metrics

  ## Root Admin

  The root admin (email matches ROOT_ADMIN_EMAIL) has all system permissions
  implicitly and does not need explicit entries in this table.
  """

  use Summoner.Domain.Schema

  import Ecto.Changeset

  alias Summoner.Domain.Schemas.User

  @permissions [
    :manage_users,
    :manage_tenants,
    :manage_system_settings,
    :view_system_stats
  ]

  schema "system_permissions" do
    field :permission, Ecto.Enum, values: @permissions

    belongs_to :user, User

    timestamps()
  end

  @doc "Returns the list of available system permissions."
  def permissions, do: @permissions

  @doc """
  Changeset for creating a system permission.
  """
  def changeset(system_permission, attrs) do
    system_permission
    |> cast(attrs, [:permission, :user_id])
    |> validate_required([:permission, :user_id])
    |> validate_inclusion(:permission, @permissions)
    |> unique_constraint([:user_id, :permission])
    |> foreign_key_constraint(:user_id)
    |> assoc_constraint(:user)
  end
end
