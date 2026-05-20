defmodule Summoner.Ports.Persistence.Workspaces do
  @moduledoc "Port for workspaces persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :workspaces],
             Summoner.Adapters.Persistence.Workspaces
           )

  # Workspace directory
  defdelegate workspace_dir(workspace_id), to: @adapter
  defdelegate open_workspace_dir(workspace_id), to: @adapter

  # Workspace CRUD
  defdelegate create_workspace(scope, tenant_id, attrs), to: @adapter
  defdelegate list_workspaces_for_user(scope), to: @adapter
  defdelegate list_workspaces_for_user_in_tenant_paginated(scope, tenant_id), to: @adapter
  defdelegate list_workspaces_for_user_in_tenant_paginated(scope, tenant_id, opts), to: @adapter
  defdelegate list_workspaces_for_user_paginated(scope), to: @adapter
  defdelegate list_workspaces_for_user_paginated(scope, opts), to: @adapter
  defdelegate get_workspace!(scope, id), to: @adapter

  # Membership management
  defdelegate list_members(scope, workspace_id), to: @adapter
  defdelegate get_membership(workspace_id, user_id), to: @adapter
  defdelegate add_member(scope, workspace_id, user_id), to: @adapter
  defdelegate add_member(scope, workspace_id, user_id, role), to: @adapter
  defdelegate remove_member(scope, workspace_id, user_id), to: @adapter
  defdelegate update_member_role(scope, workspace_id, user_id, role), to: @adapter

  # Workspace updates
  defdelegate update_workspace(scope, workspace, attrs), to: @adapter
  defdelegate delete_workspace(scope, workspace), to: @adapter

  # Settings
  defdelegate update_settings(scope, workspace, attrs), to: @adapter
  defdelegate get_settings!(workspace_id), to: @adapter

  # Query helpers
  defdelegate where_workspace(query, workspace_id), to: @adapter
end
