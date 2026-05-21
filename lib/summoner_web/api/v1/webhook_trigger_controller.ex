defmodule SummonerWeb.API.V1.WebhookTriggerController do
  @moduledoc """
  Controller for webhook trigger endpoints.

  Self-authenticated — each webhook defines its own auth mode
  (public, token, or HMAC). No TokenAuth plug.
  """

  use SummonerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Summoner.Domain.Events.ContentToken
  alias Summoner.Domain.Events.InvocationCompleted
  alias Summoner.Domain.Events.InvocationFailed
  alias Summoner.Ports.Events
  alias Summoner.Services.Webhooks, as: WebhookService
  alias SummonerWeb.API.Schemas

  tags ["webhooks"]

  operation :trigger,
    summary: "Trigger webhook",
    description:
      "Invoke the webhook's target agent/pipeline/swarm. Auth depends on webhook config (public/token/hmac).",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Trigger payload", "application/json", Schemas.WebhookTriggerParams},
    responses: [
      ok: {"Sync result", "application/json", Schemas.WebhookTriggerResult},
      accepted: {"Async accepted", "application/json", Schemas.WebhookTriggerResult},
      unauthorized: {"Unauthorized", "application/json", Schemas.ErrorResponse},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse},
      too_many_requests: {"Rate limited", "application/json", Schemas.ErrorResponse}
    ]

  def trigger(conn, %{"id" => id}) do
    auth_header = conn |> get_req_header("authorization") |> List.first()
    signature = conn |> get_req_header("x-signature-256") |> List.first()
    raw_body = conn.assigns[:raw_body]

    case WebhookService.trigger(id, conn.body_params,
           auth_header: auth_header,
           signature: signature,
           raw_body: raw_body
         ) do
      {:ok, :async, result} ->
        conn |> put_status(:accepted) |> json(result)

      {:ok, :sync, result} ->
        json(conn, result)

      {:ok, :stream, stream_info} ->
        stream_sse(conn, stream_info)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "not_found", message: "Webhook not found"}})

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "disabled", message: "Webhook is disabled"}})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "unauthorized", message: "Unauthorized"}})

      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", message: "Rate limit exceeded"}})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "trigger_failed", message: inspect(reason)}})
    end
  end

  defp stream_sse(conn, %{agent_id: agent_id, workspace_id: workspace_id}) do
    Events.subscribe({:agent, workspace_id, agent_id})

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    stream_events(conn, workspace_id, agent_id)
  end

  defp stream_events(conn, workspace_id, agent_id) do
    receive do
      %ContentToken{token: token} ->
        chunk(conn, "event: token\ndata: #{Jason.encode!(%{token: token})}\n\n")
        stream_events(conn, workspace_id, agent_id)

      %InvocationCompleted{} = event ->
        chunk(
          conn,
          "event: done\ndata: #{Jason.encode!(%{invocation_id: event.invocation_id, status: "completed"})}\n\n"
        )

        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn

      %InvocationFailed{} = event ->
        chunk(
          conn,
          "event: done\ndata: #{Jason.encode!(%{invocation_id: event.invocation_id, status: "failed"})}\n\n"
        )

        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn
    after
      :timer.minutes(5) ->
        chunk(conn, "event: timeout\ndata: {}\n\n")
        Events.unsubscribe({:agent, workspace_id, agent_id})
        conn
    end
  end
end
