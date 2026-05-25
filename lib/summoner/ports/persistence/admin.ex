defmodule Summoner.Ports.Persistence.Admin do
  @moduledoc "Port for admin persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :admin],
             Summoner.Adapters.Persistence.Admin
           )

  # Root admin / SMTP
  defdelegate root_admin?(user), to: @adapter
  defdelegate smtp_configured?, to: @adapter

  # Users
  defdelegate create_user(attrs), to: @adapter
  defdelegate list_users(), to: @adapter
  defdelegate list_users(opts), to: @adapter
  defdelegate get_user!(id), to: @adapter
  defdelegate update_user_role(user, role), to: @adapter
  defdelegate disable_user(user), to: @adapter
  defdelegate enable_user(user), to: @adapter
  defdelegate reset_user_password(user), to: @adapter
  defdelegate workspace_count_for_user(user), to: @adapter
  defdelegate list_user_workspaces(user), to: @adapter
  defdelegate first_workspace_for_user(user), to: @adapter
  defdelegate add_user_to_workspace(user, workspace_id, role \\ :member), to: @adapter
  defdelegate remove_user_from_workspace(user, workspace_id), to: @adapter

  defdelegate list_user_tenants(user), to: @adapter
  defdelegate first_tenant_for_user(user), to: @adapter
  defdelegate add_user_to_tenant(user, tenant_id, role \\ :member), to: @adapter
  defdelegate remove_user_from_tenant(user, tenant_id), to: @adapter

  # Workspaces
  defdelegate list_workspaces(), to: @adapter
  defdelegate list_workspaces(opts), to: @adapter
  defdelegate get_workspace!(id), to: @adapter
  defdelegate all_workspaces(), to: @adapter
  defdelegate member_count(workspace), to: @adapter
  defdelegate delete_workspace(workspace), to: @adapter

  # Tenants
  defdelegate list_tenants(), to: @adapter
  defdelegate list_tenants(opts), to: @adapter
  defdelegate get_tenant!(id), to: @adapter
  defdelegate tenant_member_count(tenant), to: @adapter
  defdelegate tenant_workspace_count(tenant), to: @adapter
  defdelegate disable_tenant(tenant), to: @adapter
  defdelegate enable_tenant(tenant), to: @adapter
  defdelegate delete_tenant(tenant), to: @adapter

  # System stats
  defdelegate system_stats(), to: @adapter

  # Helpers
  defdelegate generate_password(), to: @adapter

  # System permissions
  defdelegate grant_system_permission(user, permission), to: @adapter
  defdelegate revoke_system_permission(user, permission), to: @adapter
  defdelegate list_system_permissions(user), to: @adapter
  defdelegate user_has_system_permission?(user, permission), to: @adapter
end
