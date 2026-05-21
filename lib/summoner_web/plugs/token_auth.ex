defmodule SummonerWeb.Plugs.TokenAuth do
  @moduledoc """
  Plug for Bearer token authentication on API endpoints.

  Extracts a Bearer token from the `Authorization` header, verifies it
  against the access tokens for the workspace resolved from the URL,
  and assigns the token and workspace to the connection.

  ## Options

  - `:required_scope` — the scope the token must have (e.g. `"api"`, `"webhook"`).
    Defaults to `"api"`.

  ## Usage

      plug SummonerWeb.Plugs.TokenAuth, required_scope: "api"
  """

  import Plug.Conn

  alias Summoner.Ports.Persistence.AccessTokens

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    required_scope = Keyword.get(opts, :required_scope, "api")

    with {:ok, token_string} <- extract_bearer_token(conn),
         {:ok, workspace_id} <- extract_workspace_id(conn),
         {:ok, token} <- AccessTokens.verify_token(workspace_id, token_string, required_scope) do
      conn
      |> assign(:current_token, token)
      |> assign(:current_workspace_id, workspace_id)
    else
      {:error, :no_token} ->
        conn |> send_json_error(401, "missing_token", "Authorization header required") |> halt()

      {:error, :no_workspace} ->
        conn
        |> send_json_error(400, "missing_workspace", "Workspace ID required in URL")
        |> halt()

      {:error, :invalid} ->
        conn |> send_json_error(401, "invalid_token", "Invalid or revoked token") |> halt()

      {:error, :expired} ->
        conn |> send_json_error(401, "expired_token", "Token has expired") |> halt()

      {:error, :wrong_scope} ->
        conn
        |> send_json_error(
          403,
          "insufficient_scope",
          "Token does not have the required scope: #{required_scope}"
        )
        |> halt()
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :no_token}
    end
  end

  defp extract_workspace_id(conn) do
    case conn.params do
      %{"workspace_id" => workspace_id} -> {:ok, workspace_id}
      _ -> {:error, :no_workspace}
    end
  end

  defp send_json_error(conn, status, code, message) do
    body = Jason.encode!(%{error: %{code: code, message: message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end
