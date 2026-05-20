defmodule SummonerWeb.AdminLive.UserShow do
  use SummonerWeb, :live_view

  alias Summoner.Ports.Persistence.Admin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Admin.get_user!(id)
    memberships = Admin.list_user_workspaces(user)

    {:ok,
     assign(socket,
       page_title: "Admin — #{user.email}",
       user: user,
       memberships: memberships,
       reset_password: nil,
       is_root_admin: Admin.root_admin?(user)
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">{@user.email}</h1>
        <.link navigate="/archon/users" class="btn btn-ghost btn-sm">Back to Users</.link>
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
              phx-click="promote"
              class="btn btn-sm btn-primary"
              data-confirm="Promote this user to admin?"
            >
              Promote to Admin
            </button>
            <button
              :if={@user.role == "admin" && !@is_root_admin}
              phx-click="demote"
              class="btn btn-sm btn-warning"
              data-confirm="Demote this admin to regular user?"
            >
              Demote to User
            </button>
            <button
              :if={is_nil(@user.disabled_at) && !@is_root_admin}
              phx-click="disable"
              class="btn btn-sm btn-error"
              data-confirm="Disable this user? They will be logged out and unable to log in."
            >
              Disable Account
            </button>
            <button :if={@user.disabled_at} phx-click="enable" class="btn btn-sm btn-success">
              Enable Account
            </button>
            <button
              phx-click="reset_password"
              class="btn btn-sm btn-outline"
              data-confirm="Generate a new password for this user?"
            >
              Reset Password
            </button>
          </div>
        </div>
      </div>

      <%!-- Workspace memberships --%>
      <div class="space-y-2">
        <h2 class="text-lg font-semibold">Guild Memberships</h2>
        <div :if={@memberships == []} class="text-sm text-base-content/60">
          This user is not a member of any realms.
        </div>
        <div :if={@memberships != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Guild</th>
                <th>Role</th>
                <th>Joined</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={membership <- @memberships} class="hover">
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
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
