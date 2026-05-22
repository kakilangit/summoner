defmodule Summoner.Services.Plugins.ProtocolHandler do
  @moduledoc """
  Sends Summoner-extended JSON-RPC methods to plugin containers
  via their MCP client (Anubis.Client).

  Methods:
  - `summoner/webhook` — forward inbound HTTP webhook
  - `summoner/hook` — lifecycle hook (before/after invocation, on_tool_call, on_error)
  - `summoner/event` — forward domain event
  - `summoner/models` — list provider models
  - `summoner/chat` — chat completion
  - `summoner/action` — plugin → Summoner action request
  """

  alias Summoner.Adapters.Workers.PluginContainerManager

  require Logger

  @hook_timeout 5_000
  @default_timeout 30_000

  @doc "Forward a raw webhook to the plugin. Returns whatever the plugin returns."
  def send_webhook(plugin, route, headers, body) do
    call(plugin.id, "webhook", %{
      route: route,
      headers: headers,
      body: body
    })
  end

  @doc "Call a lifecycle hook. Returns proceed/modify/halt action."
  def send_hook(plugin, point, context) do
    timeout = get_hook_timeout(plugin)

    call(plugin.id, "hook", %{point: point, context: context}, timeout)
  end

  @doc "Forward a domain event to the plugin."
  def send_event(plugin, event_type, event_data, external_ref \\ nil) do
    params = %{type: event_type, data: event_data}
    params = if external_ref, do: Map.put(params, :external_ref, external_ref), else: params

    call(plugin.id, "event", params)
  end

  @doc "List models from a provider plugin."
  def list_models(plugin) do
    call(plugin.id, "models", %{})
  end

  @doc "Chat completion via a provider plugin."
  def chat(plugin, params) do
    call(plugin.id, "chat", params, 120_000)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp call(plugin_id, method, params, timeout \\ @default_timeout) do
    with {:ok, client} <- PluginContainerManager.get_client(plugin_id) do
      case Anubis.Client.call_tool(client, method, params, timeout: timeout) do
        {:ok, response} -> {:ok, normalize_result(response)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_result(%{is_error: true, result: result}), do: {:error, result}

  defp normalize_result(%{result: %{"content" => [%{"type" => "text", "text" => text} | _]}}) do
    case Jason.decode(text) do
      {:ok, parsed} -> parsed
      {:error, _} -> text
    end
  end

  defp normalize_result(%{result: result}), do: result
  defp normalize_result(other), do: other

  defp get_hook_timeout(plugin) do
    timeout = get_in(plugin.manifest, ["hooks", "timeout_ms"])

    if is_integer(timeout) and timeout > 0 and timeout <= 30_000, do: timeout, else: @hook_timeout
  end
end
