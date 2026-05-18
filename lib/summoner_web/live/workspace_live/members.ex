defmodule SummonerWeb.WorkspaceLive.Members do
  use SummonerWeb, :live_view

  import SummonerWeb.AuthorizeHelper

  alias Summoner.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace
    members = Workspaces.list_members(socket.assigns.current_scope, workspace.id)
    is_admin = socket.assigns.membership && socket.assigns.membership.role == :admin

    socket =
      socket
      |> assign(page_title: "Members - #{workspace.name}")
      |> assign(members: members, is_admin: is_admin)
      |> assign(
        breadcrumbs: [
          {"Realms", ~p"/guilds/#{workspace.tenant_id}/realms"},
          {workspace.name, ~p"/guilds/#{workspace.tenant_id}/realms/#{workspace.id}"},
          {"Members", nil}
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("remove_member", %{"user_id" => user_id}, socket) do
    authorize(socket, :manage_members, fn ->
      workspace = socket.assigns.workspace

      case Workspaces.remove_member(socket.assigns.current_scope, workspace.id, user_id) do
        {:ok, _} ->
          members = Workspaces.list_members(socket.assigns.current_scope, workspace.id)
          {:noreply, socket |> assign(members: members) |> put_flash(:info, "Member removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not remove member.")}
      end
    end)
  end

  @impl true
  def handle_event("change_role", %{"user-id" => user_id, "role" => role}, socket) do
    authorize(socket, :manage_members, fn ->
      workspace = socket.assigns.workspace
      role = String.to_existing_atom(role)

      case Workspaces.update_member_role(
             socket.assigns.current_scope,
             workspace.id,
             user_id,
             role
           ) do
        {:ok, _} ->
          members = Workspaces.list_members(socket.assigns.current_scope, workspace.id)
          {:noreply, socket |> assign(members: members) |> put_flash(:info, "Role updated.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update role.")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">Realm Members</h1>

      <div class="space-y-2">
        <div
          :for={member <- @members}
          class="flex items-center justify-between p-3 bg-base-200 rounded-lg"
        >
          <div>
            <span class="font-medium">{member.user.email}</span>
            <span class={role_badge(member.role)}>{member.role}</span>
          </div>
          <div
            :if={
              @can?.(:manage_members) && member.user.id != @current_scope.user.id &&
                member.role != :admin
            }
            class="flex gap-2"
          >
            <select
              phx-change="change_role"
              phx-value-user-id={member.user.id}
              name="role"
              class="select select-sm select-bordered"
            >
              <option value="member" selected={member.role == :member}>Member</option>
              <option value="viewer" selected={member.role == :viewer}>Viewer</option>
            </select>
            <button
              phx-click={show_confirm("#remove-member-#{member.user.id}")}
              class="btn btn-error btn-sm btn-outline"
            >
              Remove
            </button>
            <.confirm_modal
              id={"remove-member-#{member.user.id}"}
              title="Remove member?"
              message="This user will lose access to the sanctum."
              confirm_text="Remove"
              on_confirm={JS.push("remove_member", value: %{user_id: member.user.id})}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp role_badge(:admin), do: "badge badge-sm badge-primary ml-2"
  defp role_badge(:member), do: "badge badge-sm badge-info ml-2"
  defp role_badge(:viewer), do: "badge badge-sm badge-ghost ml-2"
  defp role_badge(_), do: "badge badge-sm ml-2"
end
