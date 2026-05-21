defmodule SummonerWeb.API.V1.StreamController do
  @moduledoc """
  SSE streaming endpoint for agent invocations.

  POST /api/v1/agents/:agent_id/stream

  Starts an async invocation and streams events via Server-Sent Events:
  - `token` — LLM content token
  - `invocation_started` — invocation has begun
  - `invocation_completed` — invocation finished
  - `invocation_failed` — invocation errored
  - `invocation_event` — tool lifecycle event
  - `done` — stream complete
  """

  use SummonerWeb, :controller

  alias Summoner.Domain.Events.ContentToken
  alias Summoner.Domain.Events.InvocationCompleted
  alias Summoner.Domain.Events.InvocationEvent, as: InvocationEventStruct
  alias Summoner.Domain.Events.InvocationFailed
  alias Summoner.Domain.Events.InvocationStarted
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  @stream_timeout 300_000

  def stream(conn, %{"agent_id" => agent_id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id

    agent =
      scope
      |> Agents.get_agent!(workspace_id, agent_id)
      |> Agents.preload_agent()

    message = params["message"] || ""

    conversation_id =
      case params["conversation_id"] do
        nil -> ensure_conversation(scope, workspace_id, agent)
        id -> id
      end

    # Subscribe to agent events before starting invocation
    Events.subscribe({:agent, workspace_id, agent.id})

    invoke_params = %{
      conversation_id: conversation_id,
      message: message,
      scope: scope
    }

    Agents.execute_async(agent, workspace_id, invoke_params)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    stream_events(conn, workspace_id, agent.id)
  end

  defp stream_events(conn, workspace_id, agent_id) do
    receive do
      %ContentToken{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        case send_sse(conn, "token", %{content: event.token, invocation_id: event.invocation_id}) do
          {:ok, conn} -> stream_events(conn, workspace_id, agent_id)
          {:error, _} -> conn
        end

      %InvocationStarted{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        case send_sse(conn, "invocation_started", %{invocation_id: event.invocation_id}) do
          {:ok, conn} -> stream_events(conn, workspace_id, agent_id)
          {:error, _} -> conn
        end

      %InvocationCompleted{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        send_sse(conn, "invocation_completed", %{
          invocation_id: event.invocation_id,
          output: event.output
        })

        send_sse(conn, "done", %{invocation_id: event.invocation_id})
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn

      %InvocationFailed{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        send_sse(conn, "invocation_failed", %{
          invocation_id: event.invocation_id,
          output: event.output
        })

        send_sse(conn, "done", %{invocation_id: event.invocation_id})
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn

      %InvocationEventStruct{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        case send_sse(conn, "invocation_event", %{
               invocation_id: event.invocation_id,
               event: event.event
             }) do
          {:ok, conn} -> stream_events(conn, workspace_id, agent_id)
          {:error, _} -> conn
        end

      _other ->
        stream_events(conn, workspace_id, agent_id)
    after
      @stream_timeout ->
        send_sse(conn, "timeout", %{message: "Stream timed out"})
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn
    end
  end

  defp send_sse(conn, event_type, data) do
    chunk(conn, "event: #{event_type}\ndata: #{Jason.encode!(data)}\n\n")
  end

  defp ensure_conversation(scope, workspace_id, agent) do
    {:ok, conv} =
      Conversations.create_conversation(scope, %{
        workspace_id: workspace_id,
        primary_agent_id: agent.id,
        title: "API Stream"
      })

    conv.id
  end
end
