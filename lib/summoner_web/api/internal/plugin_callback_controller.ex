defmodule SummonerWeb.API.Internal.PluginCallbackController do
  @moduledoc """
  Receives callback requests from plugin containers.

  Dispatches actions (invoke_agent, invoke_agent_async, emit_event,
  get_state, set_state, delete_state, log) via ActionExecutor.

  When `Accept: text/event-stream` is sent with `invoke_agent`, the
  response streams tokens via SSE instead of blocking until completion.

  Authenticated via `PluginCallbackAuth` plug (X-Plugin-Token header).

  SDK sends:
  - Headers: `X-Plugin-Token`, `X-Workspace-Id`, `X-Plugin-Id`
  - Body: `{"action": "<type>", "params": {...}}`

  Controller merges `action` as `type` into `params` for ActionExecutor.
  """

  use SummonerWeb, :controller

  alias Summoner.Domain.Events.ContentToken
  alias Summoner.Domain.Events.InvocationCompleted
  alias Summoner.Domain.Events.InvocationFailed
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Plugins.ActionExecutor

  require Logger

  action_fallback SummonerWeb.API.FallbackController

  @stream_timeout :timer.minutes(5)

  def callback(conn, %{"action" => "invoke_agent", "params" => params})
      when is_map(params) do
    if sse_requested?(conn) do
      handle_streaming_callback(conn, params)
    else
      handle_sync_callback(conn, "invoke_agent", params)
    end
  end

  def callback(conn, %{"action" => action_type, "params" => params})
      when is_binary(action_type) and is_map(params) do
    handle_sync_callback(conn, action_type, params)
  end

  def callback(conn, _params) do
    render_result(conn, {:error, :bad_request})
  end

  defp handle_sync_callback(conn, action_type, params) do
    workspace_id = get_header(conn, "x-workspace-id")
    plugin_id = get_header(conn, "x-plugin-id")

    case resolve_plugin(workspace_id, plugin_id) do
      {:ok, plugin} ->
        action = Map.put(params, "type", action_type)
        result = ActionExecutor.execute_action(plugin, workspace_id, action)
        render_result(conn, result)

      {:error, reason} ->
        render_result(conn, {:error, reason})
    end
  end

  defp handle_streaming_callback(conn, params) do
    workspace_id = get_header(conn, "x-workspace-id")
    plugin_id = get_header(conn, "x-plugin-id")

    case resolve_plugin(workspace_id, plugin_id) do
      {:ok, plugin} ->
        action = Map.put(params, "type", "invoke_agent")

        case ActionExecutor.start_streaming_invocation(plugin, workspace_id, action) do
          {:ok, %{agent_id: agent_id, workspace_id: ws_id}} ->
            Events.subscribe({:agent, ws_id, agent_id})

            conn =
              conn
              |> put_resp_content_type("text/event-stream")
              |> put_resp_header("cache-control", "no-cache")
              |> put_resp_header("connection", "keep-alive")
              |> put_resp_header("x-accel-buffering", "no")
              |> send_chunked(200)

            stream_invocation_events(conn, ws_id, agent_id)

          {:error, reason} ->
            render_result(conn, {:error, reason})
        end

      {:error, reason} ->
        render_result(conn, {:error, reason})
    end
  end

  defp resolve_plugin(workspace_id, plugin_id) do
    if is_binary(workspace_id) and is_binary(plugin_id) do
      {:ok, Plugins.get_plugin!(workspace_id, plugin_id)}
    else
      {:error, :bad_request}
    end
  end

  defp stream_invocation_events(conn, workspace_id, agent_id) do
    receive do
      %ContentToken{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        case send_sse(conn, "token", %{text: event.token}) do
          {:ok, conn} -> stream_invocation_events(conn, workspace_id, agent_id)
          {:error, _} -> cleanup_stream(workspace_id, agent_id)
        end

      %InvocationCompleted{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        send_sse(conn, "done", %{
          invocation_id: event.invocation_id,
          output: event.output
        })

        cleanup_stream(workspace_id, agent_id)
        conn

      %InvocationFailed{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        send_sse(conn, "error", %{message: inspect(event.output)})
        cleanup_stream(workspace_id, agent_id)
        conn

      _other ->
        stream_invocation_events(conn, workspace_id, agent_id)
    after
      @stream_timeout ->
        send_sse(conn, "error", %{message: "Stream timed out"})
        cleanup_stream(workspace_id, agent_id)
        conn
    end
  end

  defp cleanup_stream(workspace_id, agent_id) do
    Events.unsubscribe({:agent, workspace_id, agent_id})
  end

  defp send_sse(conn, event_type, data) do
    chunk(conn, "event: #{event_type}\ndata: #{Jason.encode!(data)}\n\n")
  end

  defp sse_requested?(conn) do
    case get_req_header(conn, "accept") do
      [accept] -> String.contains?(accept, "text/event-stream")
      _ -> false
    end
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
