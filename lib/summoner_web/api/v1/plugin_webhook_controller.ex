defmodule SummonerWeb.API.V1.PluginWebhookController do
  @moduledoc "Receives inbound webhooks and forwards to plugin containers."

  use SummonerWeb, :controller

  alias Summoner.Services.Plugins

  action_fallback SummonerWeb.API.FallbackController

  def trigger(conn, %{"plugin_id" => plugin_id, "route" => route}) do
    headers = conn_headers(conn)
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    body =
      case Jason.decode(body) do
        {:ok, parsed} -> parsed
        {:error, _} -> body
      end

    case Plugins.handle_webhook(plugin_id, route, headers, body) do
      {:ok, actions} ->
        json(conn, %{actions: actions})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})

      {:error, reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
    end
  end

  defp conn_headers(conn) do
    Map.new(conn.req_headers)
  end
end
