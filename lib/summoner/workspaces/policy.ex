defmodule Summoner.Workspaces.Policy do
  @moduledoc """
  Authorization policy for workspace-scoped actions.

  Checks whether a membership role has permission to perform
  a given action. Used by LiveViews and contexts to gate operations.

  ## Permission Levels

  | Action category | Required role |
  |-----------------|--------------|
  | `:manage_workspace` | `:admin` |
  | `:manage_members` | `:admin` |
  | `:delete_workspace` | `:admin` |
  | `:configure` | `:admin` |
  | `:operate` | `:member` (or higher) |
  | `:view` | `:viewer` (or higher) |
  """

  alias Summoner.Workspaces.WorkspaceMembership

  @role_hierarchy %{
    admin: 3,
    member: 2,
    viewer: 1
  }

  @action_levels %{
    manage_workspace: :admin,
    manage_members: :admin,
    delete_workspace: :admin,
    configure: :admin,
    operate: :member,
    view: :viewer
  }

  @doc """
  Returns `true` if the membership role can perform the given action.

  ## Examples

      iex> Policy.can?(%WorkspaceMembership{role: :admin}, :configure)
      true

      iex> Policy.can?(%WorkspaceMembership{role: :viewer}, :configure)
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
      raise Summoner.Workspaces.UnauthorizedError,
        action: action,
        role: membership && membership.role
    end
  end

  defp role_level(role), do: Map.get(@role_hierarchy, role, 0)
end
