defmodule Summoner.Domain.Policies.TenantPolicy do
  @moduledoc """
  Authorization policy for tenant-scoped actions.

  Checks whether a tenant membership role has permission to perform
  a given action. Used by LiveViews and contexts to gate operations.

  ## Permission Levels

  | Action category | Required role |
  |-----------------|--------------|
  | `:delete_tenant` | `:owner` |
  | `:manage_tenant_settings` | `:owner` or `:admin` |
  | `:manage_tenant_members` | `:owner` or `:admin` |
  | `:manage_shared_resources` | `:owner` or `:admin` |
  | `:create_workspaces` | `:owner` or `:admin` |
  | `:view_tenant_stats` | `:owner` or `:admin` |

  ## Usage

      # Check if membership can manage tenant settings
      if TenantPolicy.can?(membership, :manage_tenant_settings) do
        # Allow tenant settings modification
      end
  """

  alias Summoner.Domain.Schemas.TenantMembership

  @role_hierarchy %{
    owner: 3,
    admin: 2,
    member: 1
  }

  @action_levels %{
    delete_tenant: :owner,
    manage_tenant_settings: :admin,
    manage_tenant_members: :admin,
    manage_shared_resources: :admin,
    create_workspaces: :admin,
    view_tenant_stats: :admin
  }

  @doc """
  Returns `true` if the membership role can perform the given action.

  ## Examples

      iex> TenantPolicy.can?(%TenantMembership{role: :admin}, :manage_tenant_settings)
      true

      iex> TenantPolicy.can?(%TenantMembership{role: :member}, :manage_tenant_settings)
      false

      iex> TenantPolicy.can?(%TenantMembership{role: :owner}, :delete_tenant)
      true
  """
  @spec can?(TenantMembership.t() | nil, atom()) :: boolean()
  def can?(nil, _action), do: false

  def can?(%TenantMembership{role: role}, action) do
    required = Map.get(@action_levels, action)

    if required do
      role_level(role) >= role_level(required)
    else
      false
    end
  end

  @doc """
  Same as `can?/2` but raises if unauthorized.
  """
  @spec authorize!(TenantMembership.t() | nil, atom()) :: :ok
  def authorize!(membership, action) do
    if can?(membership, action) do
      :ok
    else
      raise Summoner.Domain.Policies.UnauthorizedError,
        action: action,
        role: membership && membership.role
    end
  end

  @doc """
  Returns `true` if the target role can be assigned by the grantor's role.

  Owner roles cannot be assigned by regular admins (only by other owners).

  ## Examples

      iex> TenantPolicy.can_assign_role?(:owner, :admin)
      true

      iex> TenantPolicy.can_assign_role?(:admin, :owner)
      false

      iex> TenantPolicy.can_assign_role?(:admin, :member)
      true
  """
  def can_assign_role?(grantor_role, target_role) do
    grantor_level = role_level(grantor_role)
    target_level = role_level(target_role)

    cond do
      # Owner can assign any role
      grantor_role == :owner -> true
      # Admin cannot assign owner role
      target_role == :owner -> false
      # Otherwise, check hierarchy
      true -> grantor_level >= target_level
    end
  end

  @doc """
  Returns `true` if a member with the given role can be removed from the tenant.

  Owners cannot be removed (even by other owners) unless they're the last owner.

  ## Examples

      iex> TenantPolicy.can_remove_member?(%TenantMembership{role: :owner}, tenant_has_other_owners: true)
      false

      iex> TenantPolicy.can_remove_member?(%TenantMembership{role: :admin}, tenant_has_other_owners: false)
      true
  """
  def can_remove_member?(%TenantMembership{role: :owner}, opts) do
    # Owners can only be removed if there are other owners
    not Keyword.get(opts, :is_last_owner, false)
  end

  def can_remove_member?(%TenantMembership{}, _opts), do: true

  defp role_level(role), do: Map.get(@role_hierarchy, role, 0)
end
