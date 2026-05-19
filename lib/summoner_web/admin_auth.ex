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

  alias Summoner.Domain.Schemas.Scope

  def on_mount(:ensure_admin, _params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You do not have permission to access this page.")
        |> Phoenix.LiveView.redirect(to: "/realms")

      {:halt, socket}
    end
  end
end
