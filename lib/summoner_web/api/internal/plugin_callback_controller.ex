defmodule SummonerWeb.API.Internal.PluginCallbackController do
  @moduledoc """
  Receives callback requests from plugin containers.

  Dispatches actions (invoke_agent, invoke_agent_async, emit_event,
  get_state, set_state, delete_state, log) via ActionExecutor.

  Authenticated via `PluginCallbackAuth` plug (X-Plugin-Token header).

  SDK sends:
  - Headers: `X-Plugin-Token`, `X-Workspace-Id`, `X-Plugin-Id`
  - Body: `{"action": "<type>", "params": {...}}`

  Controller merges `action` as `type` into `params` for ActionExecutor.
  """

  use SummonerWeb, :controller

  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Plugins.ActionExecutor

  require Logger

  action_fallback SummonerWeb.API.FallbackController

  def callback(conn, %{"action" => action_type, "params" => params})
      when is_binary(action_type) and is_map(params) do
    workspace_id = get_header(conn, "x-workspace-id")
    plugin_id = get_header(conn, "x-plugin-id")

    if is_binary(workspace_id) and is_binary(plugin_id) do
      plugin = Plugins.get_plugin!(workspace_id, plugin_id)
      action = Map.put(params, "type", action_type)
      result = ActionExecutor.execute_action(plugin, workspace_id, action)
      render_result(conn, result)
    else
      render_result(conn, {:error, :bad_request})
    end
  end

  def callback(conn, _params) do
    render_result(conn, {:error, :bad_request})
  end

  defp get_header(conn, name) do
    case get_req_header(conn, name) do
      [value] -> value
      _ -> nil
    end
  end

  defp render_result(conn, {:ok, :async}) do
    json(conn, %{ok: true, result: %{status: "accepted"}})
  end

  defp render_result(conn, {:ok, :emitted}) do
    json(conn, %{ok: true})
  end

  defp render_result(conn, {:ok, :logged}) do
    json(conn, %{ok: true})
  end

  defp render_result(conn, {:ok, :stored}) do
    json(conn, %{ok: true})
  end

  defp render_result(conn, {:ok, :deleted}) do
    json(conn, %{ok: true})
  end

  defp render_result(conn, {:ok, %{key: key, value: value}}) do
    json(conn, %{ok: true, result: %{key: key, value: value}})
  end

  defp render_result(conn, {:ok, invocation_result}) when is_map(invocation_result) do
    json(conn, %{ok: true, result: invocation_result})
  end

  defp render_result(conn, {:error, :agent_not_found}) do
    conn |> put_status(:not_found) |> json(%{ok: false, error: "Agent not found"})
  end

  defp render_result(conn, {:error, :unsupported_action}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "Unsupported action type"})
  end

  defp render_result(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      ok: false,
      error: "Missing required: X-Workspace-Id, X-Plugin-Id headers; action, params body fields"
    })
  end

  defp render_result(conn, {:error, reason}) do
    Logger.error("Plugin callback error: #{inspect(reason)}")
    conn |> put_status(:internal_server_error) |> json(%{ok: false, error: inspect(reason)})
  end
end
