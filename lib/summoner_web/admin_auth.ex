defmodule SummonerWeb.AdminAuth do
  @moduledoc """
  LiveView on_mount hook that ensures the current user is an admin.

  Must be used after `SummonerWeb.UserAuth :ensure_authenticated`.

  ## Usage in router

      live_session :admin,
        on_mount: [
          {SummonerWeb.UserAuth, :ensure_authenticated},
          {SummonerWeb.AdminAuth, :ensure_admin}
        ] do
        ...
      end
  """

  alias Summoner.Domain.Policies.SystemPolicy
  alias Summoner.Ports.Persistence.Admin

  def on_mount(:ensure_admin, _params, _session, socket) do
    user = socket.assigns.current_scope.user

    if admin_user?(user) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You do not have permission to access this page.")
        |> Phoenix.LiveView.redirect(to: "/workspaces")

      {:halt, socket}
    end
  end

  defp admin_user?(user) do
    SystemPolicy.root_admin?(user) or
      Enum.any?(Admin.list_system_permissions(user))
  end
end
