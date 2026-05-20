defmodule Summoner.Ports.Persistence.Tenants do
  @moduledoc "Port for tenants persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :tenants],
             Summoner.Adapters.Persistence.Tenants
           )

  # Tenant CRUD
  defdelegate create_tenant(scope, attrs), to: @adapter
  defdelegate list_tenants_for_user(scope), to: @adapter
  defdelegate get_tenant!(id), to: @adapter
  defdelegate get_tenant_by_name(name), to: @adapter
  defdelegate update_tenant(tenant, attrs), to: @adapter
  defdelegate delete_tenant(tenant), to: @adapter
  defdelegate default_tenant_for_user(scope), to: @adapter

  # Membership management
  defdelegate get_membership(tenant_id, user_id), to: @adapter
  defdelegate list_members(tenant_id), to: @adapter
  defdelegate add_member(tenant_id, user_id), to: @adapter
  defdelegate add_member(tenant_id, user_id, role), to: @adapter
  defdelegate remove_member(tenant_id, user_id), to: @adapter
  defdelegate update_member_role(tenant_id, user_id, role), to: @adapter

  # Settings
  defdelegate update_settings(tenant, attrs), to: @adapter
end
