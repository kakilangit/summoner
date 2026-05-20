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
  alias Summoner.Domain.Schemas.{Tenant, TenantMembership}
  alias Summoner.Domain.Schemas.User
  alias Summoner.Domain.Schemas.{Workspace, WorkspaceMembership}
  alias Summoner.Repo

  # -------------------------------------------------------------------
  # SMTP / Root Admin helpers
  # -------------------------------------------------------------------

  @doc "Returns true if the user is the root admin (seeded from ADMIN_EMAIL)."
  def root_admin?(%User{email: email}) do
    admin_email = Application.get_env(:summoner, :admin_email)
    admin_email != nil and String.downcase(email) == String.downcase(admin_email)
  end

  def root_admin?(_), do: false

  @doc "Returns true if SMTP is configured."
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
  def list_users(opts \\ []) do
    User
    |> order_by([u], asc: u.email)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single user by ID.

  Raises `Ecto.NoResultsError` if the user does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Updates a user's role.

  Returns `{:ok, user}` or `{:error, changeset}`.
  """
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
  def enable_user(%User{} = user) do
    user
    |> User.enable_changeset()
    |> Repo.update()
  end

  @doc """
  Generates a new random password for a user and returns `{:ok, {user, password}}`.

  The generated password is 16 characters, URL-safe base64.
  """
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
  def workspace_count_for_user(%User{id: user_id}) do
    WorkspaceMembership
    |> where([m], m.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns all workspace memberships for a user, preloading the workspace.
  """
  def list_user_workspaces(%User{id: user_id}) do
    WorkspaceMembership
    |> where([m], m.user_id == ^user_id)
    |> preload(:workspace)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Workspaces
  # -------------------------------------------------------------------

  @doc """
  Lists all workspaces with pagination. Includes member count as a virtual field.
  """
  def list_workspaces(opts \\ []) do
    Workspace
    |> order_by([w], asc: w.name)
    |> preload(:tenant)
    |> Pagination.paginate(opts)
  end

  @doc """
  Returns the member count for a workspace.
  """
  def member_count(%Workspace{id: workspace_id}) do
    WorkspaceMembership
    |> where([m], m.workspace_id == ^workspace_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a workspace by ID. Raises if not found.
  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Deletes a workspace and all associated data (cascading via DB constraints).
  """
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  # -------------------------------------------------------------------
  # Tenants
  # -------------------------------------------------------------------

  @doc """
  Lists all tenants with pagination.
  """
  def list_tenants(opts \\ []) do
    Tenant
    |> order_by([t], asc: t.name)
    |> Pagination.paginate(opts)
  end

  @doc """
  Gets a single tenant by ID. Raises if not found.
  """
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @doc """
  Returns the member count for a tenant.
  """
  def tenant_member_count(%Tenant{id: tenant_id}) do
    TenantMembership
    |> where([m], m.tenant_id == ^tenant_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the workspace count for a tenant.
  """
  def tenant_workspace_count(%Tenant{id: tenant_id}) do
    Workspace
    |> where([w], w.tenant_id == ^tenant_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Disables a tenant by setting `disabled_at`.
  """
  def disable_tenant(%Tenant{} = tenant) do
    tenant
    |> Ecto.Changeset.change(disabled_at: DateTime.utc_now())
    |> Repo.update()
  end

  @doc """
  Re-enables a disabled tenant by clearing `disabled_at`.
  """
  def enable_tenant(%Tenant{} = tenant) do
    tenant
    |> Ecto.Changeset.change(disabled_at: nil)
    |> Repo.update()
  end

  @doc """
  Deletes a tenant and all its resources (cascading).
  """
  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  # -------------------------------------------------------------------
  # System Stats
  # -------------------------------------------------------------------

  @doc """
  Returns system-wide statistics.
  """
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
  # Helpers
  # -------------------------------------------------------------------

  @doc false
  def generate_password do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
