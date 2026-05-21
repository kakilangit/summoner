defmodule SummonerWeb.OpenAI.ChatCompletionsController do
  @moduledoc """
  OpenAI-compatible `/v1/chat/completions` endpoint.

  Allows any OpenAI-compatible client (Cursor, Aider, Continue, etc.)
  to use Summoner agents as models via standard API format.
  """

  use SummonerWeb, :controller

  plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  plug SummonerWeb.Plugs.RateLimit

  alias Summoner.Domain.Policies.OpenAICompat, as: Formatter
  alias Summoner.Services.OpenAICompat

  @doc """
  POST /v1/chat/completions

  Accepts OpenAI-format request, resolves model to agent, invokes,
  and returns OpenAI-format response.
  """
  def create(conn, %{"model" => model, "messages" => messages} = _params) do
    context = %{
      workspace_id: conn.assigns.current_workspace_id,
      scope: conn.assigns.current_scope
    }

    case OpenAICompat.complete(model, messages, %{}, context) do
      {:ok, result} ->
        json(conn, result)

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

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(Formatter.format_error("Missing required fields: 'model' and 'messages'"))
  end
end
