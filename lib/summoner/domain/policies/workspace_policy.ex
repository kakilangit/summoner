defmodule Summoner.Domain.Policies.WorkspacePolicy do
  @moduledoc """
  Authorization policy for workspace-scoped actions.

  Checks whether a workspace membership role has permission to perform
  a given action. Used by LiveViews and contexts to gate operations.

  ## Permission Levels

  | Action category | Required role |
  |-----------------|--------------|
  | `:delete_workspace` | `:owner` |
  | `:manage_workspace_settings` | `:owner` or `:admin` |
  | `:manage_workspace_members` | `:owner` or `:admin` |
  | `:create_agents` | `:admin`, `:member` |
  | `:edit_any_agent` | `:owner`, `:admin` |
  | `:delete_agents` | `:owner`, `:admin` |
  | `:invoke_agents` | `:admin`, `:member` |
  | `:manage_pipelines` | `:owner`, `:admin` |
  | `:manage_swarms` | `:owner`, `:admin` |
  | `:manage_secrets` | `:owner`, `:admin` |
  | `:manage_mcp_servers` | `:owner`, `:admin` |
  | `:manage_event_rules` | `:owner`, `:admin` |
  | `:manage_approval_rules` | `:owner`, `:admin` |
  | `:view_artifacts` | `:owner`, `:admin`, `:member`, `:viewer` |
  """

  alias Summoner.Domain.Schemas.WorkspaceMembership

  @role_hierarchy %{
    owner: 4,
    admin: 3,
    member: 2,
    viewer: 1
  }

  @action_levels %{
    # New granular actions
    delete_workspace: :owner,
    manage_workspace_settings: :admin,
    manage_workspace_members: :admin,
    create_agents: :member,
    edit_any_agent: :admin,
    delete_agents: :admin,
    invoke_agents: :member,
    manage_pipelines: :admin,
    manage_swarms: :admin,
    manage_secrets: :admin,
    manage_mcp_servers: :admin,
    manage_event_rules: :admin,
    manage_approval_rules: :admin,
    view_artifacts: :viewer,
    # Legacy action aliases (kept for backward compatibility)
    manage_workspace: :admin,
    manage_members: :admin,
    configure: :admin,
    operate: :member,
    view: :viewer
  }

  @doc """
  Returns `true` if the membership role can perform the given action.

  ## Examples

      iex> WorkspacePolicy.can?(%WorkspaceMembership{role: :admin}, :manage_workspace_settings)
      true

      iex> WorkspacePolicy.can?(%WorkspaceMembership{role: :viewer}, :create_agents)
      false
  """
  @spec can?(WorkspaceMembership.t() | nil, atom()) :: boolean()
  def can?(nil, _action), do: false

  def can?(%WorkspaceMembership{role: role}, action) do
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
  @spec authorize!(WorkspaceMembership.t() | nil, atom()) :: :ok
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

  Owner roles cannot be assigned by regular admins (only by other owners or tenant admins).

  ## Examples

      iex> WorkspacePolicy.can_assign_role?(:owner, :admin)
      true

      iex> WorkspacePolicy.can_assign_role?(:admin, :owner)
      false

      iex> WorkspacePolicy.can_assign_role?(:admin, :member)
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
  Returns `true` if a member with the given role can be removed from the workspace.

  Owners cannot be removed (even by other owners) unless they're the last owner.

  ## Examples

      iex> WorkspacePolicy.can_remove_member?(%WorkspaceMembership{role: :owner}, workspace_has_other_owners: true)
      false

      iex> WorkspacePolicy.can_remove_member?(%WorkspaceMembership{role: :admin}, workspace_has_other_owners: false)
      true
  """
  def can_remove_member?(%WorkspaceMembership{role: :owner}, opts) do
    # Owners can only be removed if there are other owners
    not Keyword.get(opts, :is_last_owner, false)
  end

  def can_remove_member?(%WorkspaceMembership{}, _opts), do: true

  defp role_level(role), do: Map.get(@role_hierarchy, role, 0)
end
