defmodule SummonerWeb.Plugs.MCPAuth do
  @moduledoc """
  Authentication plug for the MCP server endpoint.

  Extracts a Bearer token from the Authorization header and resolves it
  to a workspace. For stdio transport (local dev), auth can be skipped
  via configuration.

  Unlike `TokenAuth`, this plug does NOT halt on missing auth when
  the MCP server is configured to allow unauthenticated access (stdio mode).
  """

  import Plug.Conn

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Persistence.AccessTokens

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case extract_bearer_token(conn) do
      {:ok, token_string} ->
        case AccessTokens.verify_token(token_string, scope: "api") do
          {:ok, token} ->
            conn
            |> assign(:current_token, token)
            |> assign(:current_workspace_id, token.workspace_id)
            |> assign(:current_tenant_id, token.tenant_id)
            |> assign(:current_scope, %Scope{user: nil})

          {:error, reason} ->
            conn
            |> send_json_error(401, error_message(reason))
            |> halt()
        end

      {:error, :no_token} ->
        # Allow through without auth — the MCP server init will get nil
        # workspace_id and can reject if needed.
        conn
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :no_token}
    end
  end

  defp error_message(:invalid), do: "Invalid or revoked token"
  defp error_message(:expired), do: "Token has expired"
  defp error_message(:wrong_scope), do: "Token does not have the required scope"
  defp error_message(_), do: "Authentication failed"

  defp send_json_error(conn, status, message) do
    body = Jason.encode!(%{error: %{code: "unauthorized", message: message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end
