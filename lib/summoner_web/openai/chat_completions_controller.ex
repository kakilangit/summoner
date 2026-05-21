defmodule SummonerWeb.OpenAI.ChatCompletionsController do
  @moduledoc """
  OpenAI-compatible `/v1/chat/completions` endpoint.

  Allows any OpenAI-compatible client (Cursor, Aider, Continue, etc.)
  to use Summoner agents as models via standard API format.

  Supports both non-streaming and streaming (SSE) modes.
  """

  use SummonerWeb, :controller

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  alias Summoner.Domain.Events.ContentToken
  alias Summoner.Domain.Events.InvocationCompleted
  alias Summoner.Domain.Events.InvocationFailed
  alias Summoner.Domain.Policies.OpenAICompat, as: Formatter
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Services.OpenAICompat

  @stream_timeout 300_000

  @doc """
  POST /v1/chat/completions

  Accepts OpenAI-format request, resolves model to agent, invokes,
  and returns OpenAI-format response. When `stream: true`, returns
  SSE chunks in OpenAI chunk format.
  """
  def create(conn, %{"model" => model, "messages" => messages, "stream" => true}) do
    context = %{
      workspace_id: conn.assigns.current_workspace_id,
      tenant_id: conn.assigns.current_tenant_id,
      scope: conn.assigns.current_scope
    }

    with {:ok, input} <- Formatter.extract_input(messages),
         {:ok, agent} <- OpenAICompat.resolve_agent(model, context.scope, context.workspace_id),
         {:ok, conversation_id} <- ensure_conversation(conn, context, agent) do
      stream_invocation(conn, model, agent, context, conversation_id, input)
    else
      error -> handle_error(conn, error)
    end
  end

  def create(conn, %{"model" => model, "messages" => messages} = params) do
    context = %{
      workspace_id: conn.assigns.current_workspace_id,
      tenant_id: conn.assigns.current_tenant_id,
      scope: conn.assigns.current_scope
    }

    case OpenAICompat.complete(model, messages, params, context) do
      {:ok, result} -> json(conn, result)
      error -> handle_error(conn, error)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(Formatter.format_error("Missing required fields: 'model' and 'messages'"))
  end

  # -- Streaming -------------------------------------------------------------

  defp stream_invocation(conn, model, agent, context, conversation_id, input) do
    %{workspace_id: workspace_id, scope: scope} = context

    Events.subscribe({:agent, workspace_id, agent.id})

    params = %{conversation_id: conversation_id, message: input, scope: scope}
    Agents.execute_async(agent, workspace_id, params)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    stream_loop(conn, model, workspace_id, agent.id)
  end

  defp stream_loop(conn, model, workspace_id, agent_id) do
    receive do
      %ContentToken{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        chunk_data = Formatter.format_chunk(event.invocation_id, model, event.token)

        case chunk(conn, "data: #{Jason.encode!(chunk_data)}\n\n") do
          {:ok, conn} -> stream_loop(conn, model, workspace_id, agent_id)
          {:error, _} -> conn
        end

      %InvocationCompleted{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        stop_chunk = Formatter.format_chunk(event.invocation_id, model, nil)
        chunk(conn, "data: #{Jason.encode!(stop_chunk)}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn

      %InvocationFailed{workspace_id: ^workspace_id, agent_id: ^agent_id} = event ->
        error_data = %{
          "error" => %{
            "message" => "Invocation failed: #{inspect(event.output)}",
            "type" => "server_error"
          }
        }

        chunk(conn, "data: #{Jason.encode!(error_data)}\n\n")
        chunk(conn, "data: [DONE]\n\n")
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn

      _other ->
        stream_loop(conn, model, workspace_id, agent_id)
    after
      @stream_timeout ->
        chunk(conn, "data: [DONE]\n\n")
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp ensure_conversation(conn, %{workspace_id: workspace_id, scope: scope}, agent) do
    case get_req_header(conn, "x-conversation-id") do
      [conversation_id] when conversation_id != "" ->
        {:ok, conversation_id}

      _no_header ->
        case Conversations.create_conversation(scope, %{
               workspace_id: workspace_id,
               primary_agent_id: agent.id,
               title: "OpenAI API"
             }) do
          {:ok, conv} -> {:ok, conv.id}
          {:error, _} -> {:error, :internal, "Failed to create conversation"}
        end
    end
  end

  defp handle_error(conn, error) do
    case error do
      {:error, :no_user_message} ->
        conn
        |> put_status(400)
        |> json(Formatter.format_error("No user message found in messages array"))

      {:error, :not_found, message} ->
        conn
        |> put_status(404)
        |> json(Formatter.format_error(message, "invalid_request_error", "model_not_found"))

      {:error, :invalid_model, message} ->
        conn
        |> put_status(400)
        |> json(Formatter.format_error(message))

      {:error, :not_implemented, message} ->
        conn
        |> put_status(501)
        |> json(Formatter.format_error(message, "invalid_request_error"))

      {:error, :invocation_failed, message} ->
        conn
        |> put_status(500)
        |> json(Formatter.format_error(message, "server_error"))

      {:error, :internal, message} ->
        conn
        |> put_status(500)
        |> json(Formatter.format_error(message, "server_error"))
    end
  end
end
