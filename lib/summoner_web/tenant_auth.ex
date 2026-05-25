defmodule SummonerWeb.TenantAuth do
  @moduledoc """
  LiveView on_mount hook for tenant-scoped routes.

  Fetches the tenant from the URL params and verifies the
  current user is a member. Assigns `:tenant`, `:tenant_membership`,
  and a `:tenant_can?` helper function to the socket.

  Must be used after `UserAuth :ensure_authenticated`.
  """

  import Phoenix.LiveView
  import Phoenix.Component
  use SummonerWeb, :verified_routes

  alias Summoner.Domain.Policies.SystemPolicy
  alias Summoner.Domain.Policies.TenantPolicy
  alias Summoner.Domain.Schemas.TenantMembership
  alias Summoner.Ports.Persistence.Tenants

  def on_mount(:ensure_tenant_member, params, _session, socket) do
    tenant_id = params["tenant_id"]

    if tenant_id do
      scope = socket.assigns.current_scope
      membership = Tenants.get_membership(tenant_id, scope.user.id)
      assign_tenant(socket, tenant_id, scope, membership)
    else
      {:cont, socket}
    end
  end

  defp assign_tenant(socket, tenant_id, _scope, %TenantMembership{} = membership) do
    tenant = Tenants.get_tenant!(tenant_id)

    socket =
      socket
      |> assign(:tenant, tenant)
      |> assign(:tenant_membership, membership)
      |> assign(:tenant_can?, &tenant_can?(membership, &1))

    {:cont, socket}
  end

  defp assign_tenant(socket, tenant_id, scope, nil) do
    if SystemPolicy.system_admin?(scope.user) do
      tenant = Tenants.get_tenant!(tenant_id)
      synthetic = %TenantMembership{role: :admin}

      socket =
        socket
        |> assign(:tenant, tenant)
        |> assign(:tenant_membership, synthetic)
        |> assign(:tenant_can?, fn _action -> true end)

      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You do not have access to this realm.")
        |> redirect(to: ~p"/tenants")

      {:halt, socket}
    end
  end

  defp tenant_can?(membership, :manage_resources),
    do: TenantPolicy.can?(membership, :manage_shared_resources)

  defp tenant_can?(membership, :manage_members),
    do: TenantPolicy.can?(membership, :manage_tenant_members)

  defp tenant_can?(membership, :manage_settings),
    do: TenantPolicy.can?(membership, :manage_tenant_settings)

  defp tenant_can?(membership, :delete_tenant),
    do: TenantPolicy.can?(membership, :delete_tenant)

  defp tenant_can?(membership, :create_workspaces),
    do: TenantPolicy.can?(membership, :create_workspaces)

  defp tenant_can?(membership, :view_stats),
    do: TenantPolicy.can?(membership, :view_tenant_stats)

  defp tenant_can?(membership, action),
    do: TenantPolicy.can?(membership, action)
end
