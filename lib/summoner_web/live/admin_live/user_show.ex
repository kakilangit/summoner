defmodule SummonerWeb.AdminLive.UserShow do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Admin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Admin.get_user!(id)
    tenant_memberships = Admin.list_user_tenants(user)
    workspace_memberships = Admin.list_user_workspaces(user)
    system_permissions = Admin.list_system_permissions(user)

    all_tenants = Admin.list_tenants()
    all_workspaces = Admin.all_workspaces()

    member_tenant_ids = MapSet.new(tenant_memberships, & &1.tenant_id)
    member_workspace_ids = MapSet.new(workspace_memberships, & &1.workspace_id)

    available_tenants =
      Enum.reject(all_tenants.entries || [], fn t -> MapSet.member?(member_tenant_ids, t.id) end)

    available_workspaces =
      Enum.reject(all_workspaces, fn ws -> MapSet.member?(member_workspace_ids, ws.id) end)

    {:ok,
     assign(socket,
       page_title: "Admin — #{user.email}",
       user: user,
       tenant_memberships: tenant_memberships,
       workspace_memberships: workspace_memberships,
       available_tenants: available_tenants,
       available_workspaces: available_workspaces,
       selected_tenant: "",
       selected_tenant_role: "member",
       selected_workspace: "",
       selected_workspace_role: "member",
       reset_password: nil,
       is_root_admin: Admin.root_admin?(user),
       system_permissions: system_permissions,
       is_system_admin: Enum.any?(system_permissions)
     )}
  end

  @impl true
  def handle_event("promote", _params, socket) do
    case Admin.update_user_role(socket.assigns.user, "admin") do
      {:ok, user} -> {:noreply, assign(socket, user: user)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to update role.")}
    end
  end

  def handle_event("demote", _params, socket) do
    if socket.assigns.user.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot demote yourself.")}
    else
      case Admin.update_user_role(socket.assigns.user, "user") do
        {:ok, user} ->
          {:noreply, assign(socket, user: user)}

        {:error, :root_admin_protected} ->
          {:noreply, put_flash(socket, :error, "Cannot demote the root admin.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update role.")}
      end
    end
  end

  def handle_event("disable", _params, socket) do
    if socket.assigns.user.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "You cannot disable yourself.")}
    else
      case Admin.disable_user(socket.assigns.user) do
        {:ok, user} ->
          {:noreply, assign(socket, user: user)}

        {:error, :root_admin_protected} ->
          {:noreply, put_flash(socket, :error, "Cannot disable the root admin.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to disable user.")}
      end
    end
  end

  def handle_event("enable", _params, socket) do
    case Admin.enable_user(socket.assigns.user) do
      {:ok, user} -> {:noreply, assign(socket, user: user)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to enable user.")}
    end
  end

  def handle_event("reset_password", _params, socket) do
    case Admin.reset_user_password(socket.assigns.user) do
      {:ok, {user, password}} ->
        {:noreply, assign(socket, user: user, reset_password: password)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reset password.")}
    end
  end

  def handle_event("dismiss_password", _params, socket) do
    {:noreply, assign(socket, reset_password: nil)}
  end

  def handle_event("grant_permission", %{"permission" => permission}, socket) do
    permission = String.to_existing_atom(permission)

    case Admin.grant_system_permission(socket.assigns.user, permission) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Permission granted.")
         |> assign(system_permissions: Admin.list_system_permissions(socket.assigns.user))
         |> assign(is_system_admin: true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to grant permission.")}
    end
  end

  def handle_event("revoke_permission", %{"permission" => permission}, socket) do
    permission = String.to_existing_atom(permission)

    case Admin.revoke_system_permission(socket.assigns.user, permission) do
      {:ok, :revoked} ->
        {:noreply,
         socket
         |> put_flash(:info, "Permission revoked.")
         |> assign(system_permissions: Admin.list_system_permissions(socket.assigns.user))
         |> assign(is_system_admin: Enum.any?(Admin.list_system_permissions(socket.assigns.user)))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Permission not found.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke permission.")}
    end
  end

  def handle_event("add_to_tenant", %{"tenant_id" => tenant_id, "role" => role}, socket) do
    role = String.to_existing_atom(role)

    case Admin.add_user_to_tenant(socket.assigns.user, tenant_id, role) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "User added to guild.") |> reload_memberships()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add user to guild.")}
    end
  end

  def handle_event("remove_from_tenant", %{"tenant_id" => tenant_id}, socket) do
    case Admin.remove_user_from_tenant(socket.assigns.user, tenant_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User removed from guild.") |> reload_memberships()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove user from guild.")}
    end
  end

  def handle_event("add_to_workspace", %{"workspace_id" => ws_id, "role" => role}, socket) do
    role = String.to_existing_atom(role)

    case Admin.add_user_to_workspace(socket.assigns.user, ws_id, role) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "User added to realm.") |> reload_memberships()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add user to realm.")}
    end
  end

  def handle_event("remove_from_workspace", %{"workspace_id" => ws_id}, socket) do
    case Admin.remove_user_from_workspace(socket.assigns.user, ws_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User removed from realm.") |> reload_memberships()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove user from realm.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@user.email}</h1>
        <.link navigate="/admin/users" class="btn btn-ghost btn-sm">Back to Users</.link>
      </div>

      <%!-- Reset password banner --%>
      <div :if={@reset_password} class="alert alert-warning">
        <div>
          <p class="font-semibold">
            New password generated — copy it now, it will not be shown again:
          </p>
          <code class="text-lg font-mono select-all">{@reset_password}</code>
        </div>
        <button phx-click="dismiss_password" class="btn btn-sm btn-ghost">Dismiss</button>
      </div>

      <%!-- User details --%>
      <div class="card bg-base-200">
        <div class="card-body space-y-4">
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Role</span>
              <div class="mt-1">
                <span class={[
                  "badge",
                  @user.role == "admin" && "badge-primary",
                  @user.role == "user" && "badge-ghost"
                ]}>
                  {@user.role}
                  <span :if={@is_system_admin} class="badge badge-info badge-xs ml-1">
                    System
                  </span>
                </span>
                <span :if={@is_root_admin} class="badge badge-warning badge-xs ml-1">Root</span>
              </div>
            </div>
            <div>
              <span class="text-base-content/60">Status</span>
              <div class="mt-1">
                <span :if={@user.disabled_at} class="badge badge-error">Disabled</span>
                <span
                  :if={is_nil(@user.disabled_at) && @user.confirmed_at}
                  class="badge badge-success"
                >
                  Active
                </span>
                <span
                  :if={is_nil(@user.disabled_at) && is_nil(@user.confirmed_at)}
                  class="badge badge-warning"
                >
                  Unconfirmed
                </span>
              </div>
            </div>
            <div>
              <span class="text-base-content/60">Confirmed</span>
              <div class="mt-1">
                {if @user.confirmed_at,
                  do: Summoner.Services.TimeZone.format(@user.confirmed_at),
                  else: "—"}
              </div>
            </div>
            <div>
              <span class="text-base-content/60">Registered</span>
              <div class="mt-1">
                {Summoner.Services.TimeZone.format(@user.inserted_at)}
              </div>
            </div>
          </div>

          <%!-- Actions --%>
          <div class="divider"></div>
          <div class="flex flex-wrap gap-2">
            <button
              :if={@user.role == "user" && !@is_root_admin}
              phx-click={show_confirm("#promote-confirm")}
              class="btn btn-sm btn-primary"
            >
              Promote to Admin
            </button>
            <button
              :if={@user.role == "admin" && !@is_root_admin}
              phx-click={show_confirm("#demote-confirm")}
              class="btn btn-sm btn-warning"
            >
              Demote to User
            </button>
            <button
              :if={is_nil(@user.disabled_at) && !@is_root_admin}
              phx-click={show_confirm("#disable-confirm")}
              class="btn btn-sm btn-error"
            >
              Disable Account
            </button>
            <button :if={@user.disabled_at} phx-click="enable" class="btn btn-sm btn-success">
              Enable Account
            </button>
            <button
              phx-click={show_confirm("#reset-password-confirm")}
              class="btn btn-sm btn-outline"
            >
              Reset Password
            </button>
          </div>

          <.confirm_modal
            id="promote-confirm"
            title="Promote to Admin?"
            message="This user will be promoted to admin role."
            confirm_text="Promote"
            variant="warning"
            on_confirm={JS.push("promote")}
          />
          <.confirm_modal
            id="demote-confirm"
            title="Demote to User?"
            message="This admin will be demoted to regular user role."
            confirm_text="Demote"
            variant="warning"
            on_confirm={JS.push("demote")}
          />
          <.confirm_modal
            id="disable-confirm"
            title="Disable Account?"
            message="This user will be logged out and unable to log in."
            confirm_text="Disable"
            variant="error"
            on_confirm={JS.push("disable")}
          />
          <.confirm_modal
            id="reset-password-confirm"
            title="Reset Password?"
            message="A new random password will be generated for this user."
            confirm_text="Reset"
            variant="warning"
            on_confirm={JS.push("reset_password")}
          />
        </div>
      </div>

      <%!-- System permissions --%>
      <div class="space-y-4">
        <h2 class="text-lg font-semibold">System Permissions</h2>

        <div :if={@system_permissions == []} class="text-sm text-base-content/60">
          This user has no system-level permissions.
        </div>

        <div :if={@system_permissions != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Permission</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={permission <- @system_permissions} class="hover">
                <td>
                  <span class="badge badge-sm badge-info">{permission}</span>
                </td>
                <td>
                  <button
                    phx-click={show_confirm("#revoke-permission-#{permission}")}
                    class="btn btn-error btn-xs btn-outline"
                  >
                    Revoke
                  </button>
                  <.confirm_modal
                    id={"revoke-permission-#{permission}"}
                    title="Revoke permission?"
                    message={"Revoke #{permission} from #{@user.email}?"}
                    confirm_text="Revoke"
                    on_confirm={JS.push("revoke_permission", value: %{permission: permission})}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Grant permission form --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <form phx-submit="grant_permission" class="flex items-end gap-3">
              <div class="form-control flex-1">
                <label class="label">
                  <span class="label-text">Permission</span>
                </label>
                <select name="permission" class="select select-bordered select-sm">
                  <option value="manage_users">Manage Users</option>
                  <option value="manage_tenants">Manage Tenants</option>
                  <option value="manage_system_settings">Manage System Settings</option>
                  <option value="view_system_stats">View System Stats</option>
                </select>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Grant</button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Tenant memberships --%>
      <div class="space-y-4">
        <h2 class="text-lg font-semibold">Guild Memberships</h2>

        <%!-- Add to tenant form --%>
        <div :if={@available_tenants != []} class="card bg-base-200">
          <div class="card-body">
            <form phx-submit="add_to_tenant" class="flex items-end gap-3">
              <div class="form-control flex-1">
                <label class="label">
                  <span class="label-text">Guild</span>
                </label>
                <input
                  type="text"
                  name="tenant_id"
                  list="tenant-options"
                  placeholder="Search guilds..."
                  class="input input-bordered input-sm w-full"
                  required
                  autocomplete="off"
                />
                <datalist id="tenant-options">
                  <option :for={t <- @available_tenants} value={t.id}>
                    {t.name}
                  </option>
                </datalist>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Role</span>
                </label>
                <select name="role" class="select select-bordered select-sm">
                  <option value="member" selected>Member</option>
                  <option value="admin">Admin</option>
                </select>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add</button>
            </form>
          </div>
        </div>

        <div :if={@tenant_memberships == []} class="text-sm text-base-content/60">
          This user is not a member of any guilds.
        </div>
        <div :if={@tenant_memberships != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Guild</th>
                <th>Role</th>
                <th>Joined</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={membership <- @tenant_memberships} class="hover">
                <td>{membership.tenant.name}</td>
                <td>
                  <span class="badge badge-sm badge-ghost">{membership.role}</span>
                </td>
                <td class="text-xs text-base-content/60">
                  {Summoner.Services.TimeZone.format(membership.inserted_at,
                    format: "%Y-%m-%d",
                    show_zone: false
                  )}
                </td>
                <td>
                  <button
                    phx-click={show_confirm("#remove-tenant-#{membership.tenant_id}")}
                    class="btn btn-error btn-xs btn-outline"
                  >
                    Remove
                  </button>
                  <.confirm_modal
                    id={"remove-tenant-#{membership.tenant_id}"}
                    title="Remove from guild?"
                    message={"Remove #{@user.email} from #{membership.tenant.name}?"}
                    confirm_text="Remove"
                    on_confirm={
                      JS.push("remove_from_tenant", value: %{tenant_id: membership.tenant_id})
                    }
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Workspace memberships --%>
      <div class="space-y-4">
        <h2 class="text-lg font-semibold">Realm Memberships</h2>

        <%!-- Add to workspace form --%>
        <div :if={@available_workspaces != []} class="card bg-base-200">
          <div class="card-body">
            <form phx-submit="add_to_workspace" class="flex items-end gap-3">
              <div class="form-control flex-1">
                <label class="label">
                  <span class="label-text">Realm</span>
                </label>
                <input
                  type="text"
                  name="workspace_id"
                  list="workspace-options"
                  placeholder="Search realms..."
                  class="input input-bordered input-sm w-full"
                  required
                  autocomplete="off"
                />
                <datalist id="workspace-options">
                  <option :for={ws <- @available_workspaces} value={ws.id}>
                    {ws.name} ({ws.tenant.name})
                  </option>
                </datalist>
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Role</span>
                </label>
                <select name="role" class="select select-bordered select-sm">
                  <option value="member" selected>Member</option>
                  <option value="viewer">Viewer</option>
                  <option value="admin">Admin</option>
                </select>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add</button>
            </form>
          </div>
        </div>

        <div :if={@workspace_memberships == []} class="text-sm text-base-content/60">
          This user is not a member of any realms.
        </div>
        <div :if={@workspace_memberships != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Realm</th>
                <th>Role</th>
                <th>Joined</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={membership <- @workspace_memberships} class="hover">
                <td>{membership.workspace.name}</td>
                <td>
                  <span class="badge badge-sm badge-ghost">{membership.role}</span>
                </td>
                <td class="text-xs text-base-content/60">
                  {Summoner.Services.TimeZone.format(membership.inserted_at,
                    format: "%Y-%m-%d",
                    show_zone: false
                  )}
                </td>
                <td>
                  <button
                    phx-click={show_confirm("#remove-ws-#{membership.workspace_id}")}
                    class="btn btn-error btn-xs btn-outline"
                  >
                    Remove
                  </button>
                  <.confirm_modal
                    id={"remove-ws-#{membership.workspace_id}"}
                    title="Remove from realm?"
                    message={"Remove #{@user.email} from #{membership.workspace.name}?"}
                    confirm_text="Remove"
                    on_confirm={
                      JS.push("remove_from_workspace",
                        value: %{workspace_id: membership.workspace_id}
                      )
                    }
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp reload_memberships(socket) do
    user = socket.assigns.user
    tenant_memberships = Admin.list_user_tenants(user)
    workspace_memberships = Admin.list_user_workspaces(user)

    all_tenants = Admin.list_tenants()
    all_workspaces = Admin.all_workspaces()

    member_tenant_ids = MapSet.new(tenant_memberships, & &1.tenant_id)
    member_workspace_ids = MapSet.new(workspace_memberships, & &1.workspace_id)

    available_tenants =
      Enum.reject(all_tenants.entries || [], fn t -> MapSet.member?(member_tenant_ids, t.id) end)

    available_workspaces =
      Enum.reject(all_workspaces, fn ws -> MapSet.member?(member_workspace_ids, ws.id) end)

    assign(socket,
      tenant_memberships: tenant_memberships,
      workspace_memberships: workspace_memberships,
      available_tenants: available_tenants,
      available_workspaces: available_workspaces
    )
  end
end
