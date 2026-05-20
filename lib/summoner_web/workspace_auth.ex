defmodule SummonerWeb.WorkspaceAuth do
  @moduledoc """
  LiveView on_mount hook for workspace-scoped routes.

  Fetches the workspace from the URL params and verifies the
  current user is a member. Assigns `:workspace`, `:membership`,
  and a `:can?` helper function to the socket.
  """

  import Phoenix.LiveView
  import Phoenix.Component
  use SummonerWeb, :verified_routes

  alias Summoner.Ports.Persistence.Workspaces
  alias Summoner.Domain.Policies.WorkspacePolicy
  alias Summoner.Domain.Types.Features

  def on_mount(:ensure_workspace_member, params, _session, socket) do
    workspace_id = params["workspace_id"]

    if workspace_id do
      scope = socket.assigns.current_scope

      try do
        workspace = Workspaces.get_workspace!(scope, workspace_id)
        membership = Workspaces.get_membership(workspace_id, scope.user.id)

        # Verify workspace belongs to the current tenant if tenant is assigned
        if tenant = socket.assigns[:tenant] do
          if workspace.tenant_id != tenant.id do
            raise Ecto.NoResultsError, queryable: Summoner.Domain.Schemas.Workspace
          end
        end

        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:membership, membership)
          |> assign(:can?, &WorkspacePolicy.can?(membership, &1))
          |> assign(:local_mode, Features.local_mode?())

        {:cont, socket}
      rescue
        Ecto.NoResultsError ->
          redirect_path =
            if socket.assigns[:tenant],
              do: ~p"/guilds/#{socket.assigns.tenant.id}/realms",
              else: ~p"/guilds"

          socket =
            socket
            |> put_flash(:info, "The requested realm is not available. Here are your realms.")
            |> redirect(to: redirect_path)

          {:halt, socket}
      end
    else
      {:cont, socket}
    end
  end
end
