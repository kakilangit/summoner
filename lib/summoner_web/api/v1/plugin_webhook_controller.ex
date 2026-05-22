defmodule SummonerWeb.API.V1.PluginWebhookController do
  @moduledoc """
  Receives inbound webhooks and forwards to plugin containers.

  Pure HTTP response forwarding — plugins use the callback API
  for actions (invoke_agent, emit_event, etc.) instead of returning
  actions in webhook responses.
  """

  use SummonerWeb, :controller

  alias Summoner.Services.Plugins

  require Logger

  action_fallback SummonerWeb.API.FallbackController

  def trigger(conn, %{"plugin_ref" => plugin_ref, "route" => route}) do
    workspace_id = conn.assigns.current_workspace_id
    headers = conn_headers(conn)
    raw_body = conn.assigns[:raw_body] || ""

    case Plugins.handle_webhook(workspace_id, plugin_ref, route, headers, raw_body) do
      {:ok, %{"status" => status, "headers" => resp_headers, "body" => body}} ->
        conn
        |> set_resp_headers(resp_headers)
        |> put_status(status)
        |> json(body)

      {:ok, %{"body" => body}} ->
        json(conn, body)

      {:ok, response} ->
        json(conn, response)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Plugin not found"})

      {:error, :plugin_not_enabled} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "Plugin not enabled"})

      {:error, reason} ->
        Logger.error("Plugin webhook error: #{inspect(reason)}")
        conn |> put_status(:internal_server_error) |> json(%{error: inspect(reason)})
    end
  end

  defp set_resp_headers(conn, headers) when is_map(headers) do
    Enum.reduce(headers, conn, fn {k, v}, acc ->
      put_resp_header(acc, k, v)
    end)
  end

  defp set_resp_headers(conn, _), do: conn

  defp conn_headers(conn) do
    Map.new(conn.req_headers)
  end
end
