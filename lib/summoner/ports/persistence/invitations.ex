defmodule Summoner.Ports.Persistence.Invitations do
  @moduledoc "Port for invitations persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :invitations],
             Summoner.Adapters.Persistence.Invitations
           )

  # Invitations
  defdelegate create_tenant_invitation(user, tenant_id), to: @adapter
  defdelegate use_invitation(code, user), to: @adapter
  defdelegate get_invitation_by_code(code), to: @adapter
  defdelegate get_invitation!(id), to: @adapter
  defdelegate list_all_invitations(), to: @adapter
  defdelegate list_all_invitations(opts), to: @adapter
  defdelegate list_tenant_invitations(tenant_id), to: @adapter
  defdelegate list_tenant_invitations(tenant_id, opts), to: @adapter
  defdelegate list_user_tenant_invitations(user, tenant_id), to: @adapter
  defdelegate list_user_tenant_invitations(user, tenant_id, opts), to: @adapter

  # Quotas
  defdelegate remaining_quota(user, tenant_id), to: @adapter
  defdelegate add_quota(user, tenant_id, amount), to: @adapter
  defdelegate get_quota(user_id, tenant_id), to: @adapter
  defdelegate list_all_quotas(), to: @adapter
  defdelegate list_all_quotas(opts), to: @adapter
  defdelegate list_tenant_quotas(tenant_id), to: @adapter
  defdelegate list_tenant_quotas(tenant_id, opts), to: @adapter
end
