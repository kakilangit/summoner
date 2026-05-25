defmodule Summoner.Domain.Policies.SystemPolicy do
  @moduledoc """
  Authorization policy for system-level actions.

  Pure functions for checking system-level permissions. This module contains
  no side effects and no database queries — it only evaluates permissions
  based on input data.

  ## Permissions

  - `:manage_users` - Create, update, disable users; manage user roles and permissions
  - `:manage_tenants` - Create, update, disable tenants
  - `:manage_system_settings` - Modify system-wide configuration
  - `:view_system_stats` - View system-wide statistics and metrics

  ## Root Admin

  The root admin (email matches `ROOT_ADMIN_EMAIL` env var) has all system
  permissions implicitly.

  ## Usage

      # Check if user is root admin
      if SystemPolicy.root_admin?(user) do
        # Root admin has all permissions
      end

      # Check if user has specific permission (requires preloaded permissions)
      if SystemPolicy.can?(user, :manage_users, user_permissions) do
        # Allow user management
      end
  """

  alias Summoner.Domain.Schemas.User

  @system_permissions [
    :manage_users,
    :manage_tenants,
    :manage_system_settings,
    :view_system_stats
  ]

  @doc """
  Returns the list of all system permissions.
  """
  def permissions, do: @system_permissions

  @doc """
  Returns `true` if the user is the root admin (email matches ROOT_ADMIN_EMAIL env var).

  ## Examples

      iex> SystemPolicy.root_admin?(%User{email: "root@example.com"})
      true

      iex> SystemPolicy.root_admin?(%User{email: "user@example.com"})
      false
  """
  def root_admin?(%User{email: email}) when is_binary(email) do
    admin_email = Application.get_env(:summoner, :admin_email)
    admin_email != nil and String.downcase(email) == String.downcase(admin_email)
  end

  def root_admin?(%{email: email}) when is_binary(email) do
    admin_email = Application.get_env(:summoner, :admin_email)
    admin_email != nil and String.downcase(email) == String.downcase(admin_email)
  end

  def root_admin?(_), do: false

  @doc """
  Returns `true` if the user has the specified system permission.

  Root admin always returns `true` for all permissions.
  Regular users must have the permission in their preloaded permissions list.

  ## Parameters

  - `user` - The user struct or map with `:email` field
  - `permission` - The permission atom to check
  - `user_permissions` - List of permissions granted to the user (from `system_permissions` table)

  ## Examples

      iex> SystemPolicy.can?(user, :manage_users, [:manage_users, :view_system_stats])
      true

      iex> SystemPolicy.can?(user, :manage_tenants, [:view_system_stats])
      false
  """
  def can?(user, permission, user_permissions \\ [])

  def can?(user, _permission, _user_permissions) when is_nil(user), do: false

  def can?(user, permission, user_permissions) when permission in @system_permissions do
    root_admin?(user) or permission in user_permissions
  end

  def can?(_, _, _), do: false

  @doc """
  Returns `true` if the user has any system-level permissions (either as root admin
  or via explicit system_permissions).

  ## Parameters

  - `user` - The user struct or map with `:email` field
  - `user_permissions` - List of permissions granted to the user

  ## Examples

      iex> SystemPolicy.system_admin?(user, [:manage_users])
      true
  """
  def system_admin?(user, user_permissions \\ [])

  def system_admin?(user, []), do: root_admin?(user)

  def system_admin?(user, user_permissions) do
    root_admin?(user) or Enum.any?(user_permissions)
  end
end
