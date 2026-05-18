defmodule SummonerWeb.AuthorizeHelper do
  @moduledoc """
  Helper functions for role-based authorization in LiveViews.

  Import this in LiveViews that need to gate actions by workspace role.
  """

  import Phoenix.LiveView

  alias Summoner.Workspaces.Policy

  @doc """
  Checks if the current membership can perform the action.
  If authorized, executes the callback. Otherwise, adds an error flash.

  ## Example

      authorize(socket, :configure, fn ->
        # do the thing
        {:noreply, socket}
      end)
  """
  def authorize(socket, action, callback) do
    membership = socket.assigns.membership

    if Policy.can?(membership, action) do
      callback.()
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to do that.")}
    end
  end
end
