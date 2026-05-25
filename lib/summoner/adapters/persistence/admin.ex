defmodule Summoner.Adapters.Persistence.Admin do
  @moduledoc """
  Admin context for system-wide user and workspace management.

  All functions in this module are intended for admin-only use.
  Authorization is enforced at the router/LiveView level via AdminAuth.
  """

  @behaviour Summoner.Ports.Persistence.Admin.Adapter

  import Ecto.Query, warn: false

  alias Summoner.Adapters.Persistence.Accounts
  alias Summoner.Adapters.Persistence.Pagination
  alias Summoner.Domain.Schemas.{SystemPermission, Tenant, TenantMembership}
  alias Summoner.Domain.Schemas.User
  alias Summoner.Domain.Schemas.{Workspace, WorkspaceMembership}
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # SMTP / Root Admin helpers
  # -------------------------------------------------------------------

  @doc "Returns true if the user is the root admin (seeded from ADMIN_EMAIL)."
  @impl true
  def root_admin?(%User{email: email}) do
    admin_email = Application.get_env(:summoner, :admin_email)
    admin_email != nil and String.downcase(email) == String.downcase(admin_email)
  end

  @impl true
  def root_admin?(_), do: false

  @doc "Returns true if SMTP is configured."
  @impl true
  def smtp_configured? do
    Application.get_env(:summoner, :smtp_configured?, false)
  end

  # -------------------------------------------------------------------
  # Users
  # -------------------------------------------------------------------

  @doc """
  Creates a user with email, password, optional role, and auto-confirms them.

  Intended for admin-created users who bypass email confirmation.
  """
  @impl true
  def create_user(attrs) do
    email = attrs[:email] || attrs["email"]
    password = attrs[:password] || attrs["password"]
    role = attrs[:role] || attrs["role"] || "user"

    Repo.transact(fn ->
      with {:ok, user} <- Accounts.register_user(%{email: email}),
           {:ok, user} <- set_user_password(user, password) do
        confirm_and_set_role(user, role)
      end
    end)
  end

  defp set_user_password(user, password) do
    user
    |> User.password_changeset(%{password: password})
    |> Repo.update()
  end

  defp confirm_and_set_role(user, role) do
    user
    |> User.confirm_changeset()
    |> Ecto.Changeset.put_change(:role, role)
    |> Repo.update()
  end

  @doc """
  Lists all users with pagination.
  """
  @impl true
  def list_users(opts \\ []) do
    User
    |> order_by([u], asc: u.email)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single user by ID.

  Raises `Ecto.NoResultsError` if the user does not exist.
  """
  @impl true
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Updates a user's role.

  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  @impl true
  def update_user_role(%User{} = user, role) when role in ~w(user admin) do
    if root_admin?(user) and role == "user" do
      {:error, :root_admin_protected}
    else
      user
      |> User.role_changeset(%{role: role})
      |> Repo.update()
    end
  end

  @doc """
  Disables a user account by setting `disabled_at`.

  Disabled users cannot log in or access authenticated routes.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  @impl true
  def disable_user(%User{} = user) do
    if root_admin?(user) do
      {:error, :root_admin_protected}
    else
      user
      |> User.disable_changeset()
      |> Repo.update()
    end
  end

  @doc """
  Re-enables a disabled user account by clearing `disabled_at`.

  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  @impl true
  def enable_user(%User{} = user) do
    user
    |> User.enable_changeset()
    |> Repo.update()
  end

  @doc """
  Generates a new random password for a user and returns `{:ok, {user, password}}`.

  The generated password is 16 characters, URL-safe base64.
  """
  @impl true
  def reset_user_password(%User{} = user) do
    password = generate_password()

    case user |> User.password_changeset(%{password: password}) |> Repo.update() do
      {:ok, user} -> {:ok, {user, password}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Returns the count of workspaces the user is a member of.
  """
  @impl true
  def workspace_count_for_user(%User{id: user_id}) do
    WorkspaceMembership
    |> where([m], m.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns all workspace memberships for a user, preloading the workspace.
  """
  @impl true
  def list_user_workspaces(%User{id: user_id}) do
    WorkspaceMembership
    |> where([m], m.user_id == ^user_id)
    |> preload(:workspace)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the first workspace for a user (by join date), preloading tenant and workspace.
  Returns nil if the user has no workspace memberships.
  """
  @impl true
  def first_workspace_for_user(%User{id: user_id}) do
    WorkspaceMembership
    |> where([m], m.user_id == ^user_id)
    |> join(:inner, [m], w in assoc(m, :workspace))
    |> preload([m, w], workspace: {w, :tenant})
    |> order_by([m], asc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Adds a user to a workspace with the given role.

  Automatically creates a tenant membership (as `:member`) if the user
  is not already a member of the workspace's parent tenant.
  """
  @impl true
  def add_user_to_workspace(%User{id: user_id}, workspace_id, role \\ :member) do
    Repo.transact(fn ->
      workspace = Repo.get!(Workspace, workspace_id)

      ensure_tenant_membership(user_id, workspace.tenant_id)

      %WorkspaceMembership{}
      |> WorkspaceMembership.changeset(%{
        user_id: user_id,
        workspace_id: workspace_id,
        role: role
      })
      |> Repo.insert()
    end)
  end

  defp ensure_tenant_membership(user_id, tenant_id) do
    unless Repo.exists?(
             from(tm in TenantMembership,
               where: tm.user_id == ^user_id and tm.tenant_id == ^tenant_id
             )
           ) do
      %TenantMembership{}
      |> TenantMembership.changeset(%{user_id: user_id, tenant_id: tenant_id, role: :member})
      |> Repo.insert!()
    end
  end

  @doc """
  Removes a user from a workspace.
  """
  @impl true
  def remove_user_from_workspace(%User{id: user_id}, workspace_id) do
    case Repo.get_by(WorkspaceMembership, user_id: user_id, workspace_id: workspace_id) do
      nil -> {:error, :not_found}
      membership -> Repo.delete(membership)
    end
  end

  # -------------------------------------------------------------------
  # Tenants
  # -------------------------------------------------------------------

  @doc """
  Lists all tenant memberships for a user, preloading the tenant.
  """
  @impl true
  def list_user_tenants(%User{id: user_id}) do
    TenantMembership
    |> where([m], m.user_id == ^user_id)
    |> preload(:tenant)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the first tenant for a user (by join date), preloading tenant.
  Returns nil if the user has no tenant memberships.
  """
  @impl true
  def first_tenant_for_user(%User{id: user_id}) do
    TenantMembership
    |> where([m], m.user_id == ^user_id)
    |> join(:inner, [m], t in assoc(m, :tenant))
    |> preload([m, t], tenant: t)
    |> order_by([m], asc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Adds a user to a tenant with the given role.
  """
  @impl true
  def add_user_to_tenant(%User{id: user_id}, tenant_id, role \\ :member) do
    %TenantMembership{}
    |> TenantMembership.changeset(%{user_id: user_id, tenant_id: tenant_id, role: role})
    |> Repo.insert()
  end

  @doc """
  Removes a user from a tenant.
  """
  @impl true
  def remove_user_from_tenant(%User{id: user_id}, tenant_id) do
    case Repo.get_by(TenantMembership, user_id: user_id, tenant_id: tenant_id) do
      nil -> {:error, :not_found}
      membership -> Repo.delete(membership)
    end
  end

  # -------------------------------------------------------------------
  # Workspaces
  # -------------------------------------------------------------------

  @doc """
  Lists all workspaces with pagination. Includes member count as a virtual field.
  """
  @impl true
  def list_workspaces(opts \\ []) do
    Workspace
    |> order_by([w], asc: w.name)
    |> preload(:tenant)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns all workspaces as a flat list (no pagination), for use in admin assignment UIs.
  """
  @impl true
  def all_workspaces do
    Workspace
    |> order_by([w], asc: w.name)
    |> preload(:tenant)
    |> Repo.all()
  end

  @doc """
  Returns the member count for a workspace.
  """
  @impl true
  def member_count(%Workspace{id: workspace_id}) do
    WorkspaceMembership
    |> where([m], m.workspace_id == ^workspace_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a workspace by ID. Raises if not found.
  """
  @impl true
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Deletes a workspace and all associated data (cascading via DB constraints).
  """
  @impl true
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  # -------------------------------------------------------------------
  # Tenants
  # -------------------------------------------------------------------

  @doc """
  Lists all tenants with pagination.
  """
  @impl true
  def list_tenants(opts \\ []) do
    Tenant
    |> order_by([t], asc: t.name)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single tenant by ID. Raises if not found.
  """
  @impl true
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @doc """
  Returns the member count for a tenant.
  """
  @impl true
  def tenant_member_count(%Tenant{id: tenant_id}) do
    TenantMembership
    |> where([m], m.tenant_id == ^tenant_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the workspace count for a tenant.
  """
  @impl true
  def tenant_workspace_count(%Tenant{id: tenant_id}) do
    Workspace
    |> where([w], w.tenant_id == ^tenant_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Disables a tenant by setting `disabled_at`.
  """
  @impl true
  def disable_tenant(%Tenant{} = tenant) do
    tenant
    |> Ecto.Changeset.change(disabled_at: DateTime.utc_now())
    |> Repo.update()
  end

  @doc """
  Re-enables a disabled tenant by clearing `disabled_at`.
  """
  @impl true
  def enable_tenant(%Tenant{} = tenant) do
    tenant
    |> Ecto.Changeset.change(disabled_at: nil)
    |> Repo.update()
  end

  @doc """
  Deletes a tenant and all its resources (cascading).
  """
  @impl true
  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  # -------------------------------------------------------------------
  # System Stats
  # -------------------------------------------------------------------

  @doc """
  Returns system-wide statistics.
  """
  @impl true
  def system_stats do
    %{
      user_count: Repo.aggregate(User, :count),
      tenant_count: Repo.aggregate(Tenant, :count),
      workspace_count: Repo.aggregate(Workspace, :count),
      agent_count: count_table("agents"),
      invocation_count: count_table("invocations")
    }
  end

  defp count_table(table) do
    Repo.one(from(t in table, select: count()))
  end

  # -------------------------------------------------------------------
  # System Permissions
  # -------------------------------------------------------------------

  @doc """
  Grants a system permission to a user.

  Only root admin should call this function.
  """
  @impl true
  def grant_system_permission(%User{id: user_id}, permission) do
    %SystemPermission{}
    |> SystemPermission.changeset(%{user_id: user_id, permission: permission})
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:user_id, :permission]
    )
  end

  @doc """
  Revokes a system permission from a user.

  Only root admin should call this function.
  """
  @impl true
  def revoke_system_permission(%User{id: user_id}, permission) do
    from(p in SystemPermission,
      where: p.user_id == ^user_id and p.permission == ^permission
    )
    |> Repo.delete_all()
    |> case do
      {1, _} -> {:ok, :revoked}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Lists all system permissions granted to a user.
  """
  @impl true
  def list_system_permissions(%User{id: user_id}) do
    from(p in SystemPermission,
      where: p.user_id == ^user_id,
      select: p.permission
    )
    |> Repo.all()
  end

  @doc """
  Returns true if the user has the specified system permission.
  """
  @impl true
  def user_has_system_permission?(%User{id: user_id}, permission) do
    Repo.exists?(
      from(p in SystemPermission,
        where: p.user_id == ^user_id and p.permission == ^permission
      )
    )
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  @doc false
  @impl true
  def generate_password do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
