defmodule SummonerWeb.API.V1.InvocationController do
  @moduledoc """
  REST API controller for agent invocations.

  Handles sync invoke, invocation observability, and cancellation.
  Streaming is handled by `StreamController`.
  """

  use SummonerWeb, :controller

  import SummonerWeb.API.PaginationParams

  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Orchestration
  alias Summoner.Services.Orchestration.Cancellation

  action_fallback SummonerWeb.API.FallbackController

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  @doc """
  POST /api/v1/agents/:agent_id/invoke

  Synchronously invokes an agent. Blocks until the invocation completes
  (up to 5 minutes). Returns the invocation result with messages.

  Body:
    - `message` (required) — the user message
    - `conversation_id` (optional) — reuse an existing conversation
  """
  def invoke(conn, %{"agent_id" => agent_id} = params) do
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

    invoke_params = %{
      conversation_id: conversation_id,
      message: message,
      scope: scope
    }

    case Agents.execute_sync(agent, workspace_id, invoke_params) do
      {:ok, invocation} ->
        messages = Conversations.list_messages(conversation_id)
        render(conn, :invocation, invocation: invocation, messages: messages)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "invocation_failed", message: inspect(reason)}})
    end
  end

  @doc "GET /api/v1/invocations/:id — get invocation status and details"
  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    invocation = Orchestration.get_invocation!(scope, workspace_id, id)
    render(conn, :show, invocation: invocation)
  end

  @doc "GET /api/v1/invocations/:id/steps — detailed step log"
  def steps(conn, %{"invocation_id" => invocation_id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _invocation = Orchestration.get_invocation!(scope, workspace_id, invocation_id)
    page = Orchestration.list_steps_paginated(invocation_id, pagination_opts(params))
    render(conn, :steps, page: page)
  end

  @doc "GET /api/v1/invocations/:id/events — event timeline"
  def events(conn, %{"invocation_id" => invocation_id} = params) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _invocation = Orchestration.get_invocation!(scope, workspace_id, invocation_id)
    page = Orchestration.list_events_paginated(invocation_id, pagination_opts(params))
    render(conn, :events, page: page)
  end

  @doc "POST /api/v1/invocations/:id/cancel — cancel a running invocation"
  def cancel(conn, %{"invocation_id" => invocation_id}) do
    scope = conn.assigns.current_scope
    workspace_id = conn.assigns.current_workspace_id
    _invocation = Orchestration.get_invocation!(scope, workspace_id, invocation_id)

    Cancellation.cancel_tree(invocation_id)

    send_resp(conn, :accepted, "")
  end

  defp ensure_conversation(scope, workspace_id, agent) do
    {:ok, conv} =
      Conversations.create_conversation(scope, %{
        workspace_id: workspace_id,
        primary_agent_id: agent.id,
        title: "API Invocation"
      })

    conv.id
  end
end
