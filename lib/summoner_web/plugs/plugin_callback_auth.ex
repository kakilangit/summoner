defmodule SummonerWeb.Plugs.PluginCallbackAuth do
  @moduledoc """
  Plug that authenticates plugin callback requests.

  Verifies `X-Plugin-Token` header against known container callback tokens.
  Assigns the matched `plugin_container` to the connection.

  The controller reads `workspace_id` and `plugin_id` from the request body.
  """

  import Plug.Conn

  alias Summoner.Domain.Schemas.PluginContainer
  alias Summoner.Repo

  import Ecto.Query

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with [token] <- get_req_header(conn, "x-plugin-token"),
         %PluginContainer{} = container <- lookup_container(token) do
      assign(conn, :plugin_container, container)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid or missing plugin token"})
        |> halt()
    end
  end

  defp lookup_container(token) do
    PluginContainer
    |> where([c], c.callback_token == ^token and c.status == :running)
    |> Repo.one()
  end
end
