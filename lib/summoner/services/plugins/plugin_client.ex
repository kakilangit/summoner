defmodule Summoner.Services.Plugins.PluginClient do
  @moduledoc """
  HTTP client for communicating with plugin containers.

  Replaces `ProtocolHandler` (MCP/stdio). Uses `Req` to POST JSON
  to the plugin's axum HTTP server.
  """

  alias Summoner.Ports.ContainerRuntime

  require Logger

  @default_timeout 30_000
  @hook_timeout 5_000

  @doc "Forward a webhook to the plugin container."
  def send_webhook(container, context, route, headers, body) do
    post(container, "/webhook", %{
      context: context,
      route: route,
      headers: headers,
      body: body
    })
  end

  @doc "Forward a domain event to the plugin container."
  def send_event(container, context, event_type, data, external_ref \\ nil) do
    post(container, "/event", %{
      context: context,
      event_type: event_type,
      data: data,
      external_ref: external_ref
    })
  end

  @doc "Call a lifecycle hook on the plugin container."
  def send_hook(container, context, point, data, timeout \\ @hook_timeout) do
    post(container, "/hook", %{context: context, point: point, data: data}, timeout)
  end

  @doc "Call a tool on the plugin container."
  def call_tool(container, context, name, arguments) do
    post(container, "/tool", %{context: context, name: name, arguments: arguments})
  end

  @doc "Health check the plugin container."
  def health(container) do
    ContainerRuntime.health_check(container.host, container.port)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp post(container, path, body, timeout \\ @default_timeout) do
    url = base_url(container) <> path

    case Req.post(url, json: body, receive_timeout: timeout) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        error = if is_map(resp_body), do: Map.get(resp_body, "error", "unknown"), else: resp_body
        {:error, {:plugin_error, status, error}}

      {:error, reason} ->
        Logger.warning("PluginClient POST #{url} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp base_url(container) do
    "http://#{container.host}:#{container.port}"
  end
end
