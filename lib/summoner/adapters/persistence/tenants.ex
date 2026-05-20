defmodule Summoner.Adapters.Persistence.Tenants do
  @moduledoc """
  The Tenants context.

  Manages tenants, memberships, and tenant-level settings.
  Tenants are the top-level organizational boundary — workspaces
  belong to tenants, and resources can be shared at the tenant level.
  """

  @behaviour Summoner.Ports.Persistence.Tenants.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Domain.Schemas.{Tenant, TenantMembership, TenantSettings}
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # Tenant CRUD
  # -------------------------------------------------------------------

  @doc """
  Creates a tenant with the given user as owner.

  Atomically creates the tenant, an owner membership, and default settings.
  """
  def create_tenant(%{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, tenant} <- Repo.insert(Tenant.changeset(%Tenant{}, attrs)),
           {:ok, _membership} <-
             Repo.insert(
               TenantMembership.changeset(%TenantMembership{}, %{
                 tenant_id: tenant.id,
                 user_id: user.id,
                 role: :admin
               })
             ),
           {:ok, settings} <-
             Repo.insert(
               TenantSettings.changeset(%TenantSettings{}, %{
                 tenant_id: tenant.id
               })
             ) do
        {:ok, %{tenant | settings: settings}}
      end
    end)
  end

  @doc """
  Lists all tenants the given user is a member of.
  """
  def list_tenants_for_user(%{user: user}) do
    Tenant
    |> join(:inner, [t], m in TenantMembership, on: m.tenant_id == t.id)
    |> where([_t, m], m.user_id == ^user.id)
    |> where([t], is_nil(t.disabled_at))
    |> order_by([t], asc: t.name)
    |> preload(:settings)
    |> Repo.all()
  end

  @doc """
  Gets a single tenant by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_tenant!(id) do
    Tenant
    |> preload(:settings)
    |> Repo.get!(id)
  end

  @doc """
  Gets a tenant by name.

  Returns `nil` if not found.
  """
  def get_tenant_by_name(name) do
    Tenant
    |> where([t], t.name == ^name)
    |> preload(:settings)
    |> Repo.one()
  end

  @doc """
  Updates a tenant.
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tenant and all its resources (cascading).
  """
  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  @doc """
  Returns the default tenant for a user (first tenant by name).

  Returns `nil` if the user has no tenants.
  """
  def default_tenant_for_user(%{user: user}) do
    Tenant
    |> join(:inner, [t], m in TenantMembership, on: m.tenant_id == t.id)
    |> where([_t, m], m.user_id == ^user.id)
    |> where([t], is_nil(t.disabled_at))
    |> order_by([t], asc: t.name)
    |> limit(1)
    |> preload(:settings)
    |> Repo.one()
  end

  # -------------------------------------------------------------------
  # Membership management
  # -------------------------------------------------------------------

  @doc """
  Gets the membership for a user in a tenant.

  Returns `nil` if not found.
  """
  def get_membership(tenant_id, user_id) do
    Repo.get_by(TenantMembership, tenant_id: tenant_id, user_id: user_id)
  end

  @doc """
  Lists members of a tenant with their user data.
  """
  def list_members(tenant_id) do
    TenantMembership
    |> where([m], m.tenant_id == ^tenant_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Adds a user to a tenant with the given role.
  """
  def add_member(tenant_id, user_id, role \\ :member) do
    %TenantMembership{}
    |> TenantMembership.changeset(%{
      tenant_id: tenant_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user from a tenant.
  """
  def remove_member(tenant_id, user_id) do
    case Repo.get_by(TenantMembership, tenant_id: tenant_id, user_id: user_id) do
      nil -> {:error, :not_found}
      membership -> Repo.delete(membership)
    end
  end

  @doc """
  Updates a member's role in a tenant.
  """
  def update_member_role(tenant_id, user_id, role) do
    case Repo.get_by(TenantMembership, tenant_id: tenant_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      membership ->
        membership
        |> TenantMembership.changeset(%{role: role})
        |> Repo.update()
    end
  end

  # -------------------------------------------------------------------
  # Settings management
  # -------------------------------------------------------------------

  @doc """
  Updates tenant settings.
  """
  def update_settings(%Tenant{} = tenant, attrs) do
    tenant
    |> Ecto.assoc(:settings)
    |> Repo.one!()
    |> TenantSettings.changeset(attrs)
    |> Repo.update()
  end
end
