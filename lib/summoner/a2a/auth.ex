defmodule Summoner.A2A.Auth do
  @moduledoc """
  Authentication verification for A2A inbound requests.

  Implements the `verify/3` callback used by `A2A.Plug.Auth` to validate
  credentials against the A2A server's configured auth mode and key hash.
  """

  alias Summoner.A2A.A2AServer

  @doc """
  Verifies a credential extracted by `A2A.Plug.Auth`.

  Returns `{:ok, identity}` on success or `{:error, reason}` on failure.
  The identity map is stored in `conn.private[:a2a][:auth]` and becomes
  `metadata["a2a.auth"]` in JSON-RPC calls.
  """
  @spec verify(String.t(), String.t(), Plug.Conn.t()) ::
          {:ok, map()} | {:error, String.t()}
  def verify(scheme_name, credential, conn) do
    a2a_server = conn.private[:a2a_server]

    if a2a_server do
      verify_credential(a2a_server, scheme_name, credential)
    else
      {:error, "No A2A server context"}
    end
  end

  defp verify_credential(%A2AServer{auth_mode: :none}, _scheme, _credential) do
    {:ok, %{auth_mode: :none}}
  end

  defp verify_credential(%A2AServer{auth_mode: :bearer_token} = server, "bearer", token) do
    if Bcrypt.verify_pass(token, server.api_key_hash) do
      {:ok, %{server_id: server.id, workspace_id: server.workspace_id, auth_mode: :bearer_token}}
    else
      {:error, "Invalid bearer token"}
    end
  end

  defp verify_credential(%A2AServer{auth_mode: :api_key} = server, "api_key", key) do
    if Bcrypt.verify_pass(key, server.api_key_hash) do
      {:ok, %{server_id: server.id, workspace_id: server.workspace_id, auth_mode: :api_key}}
    else
      {:error, "Invalid API key"}
    end
  end

  defp verify_credential(_server, scheme, _credential) do
    {:error, "Unsupported auth scheme: #{scheme}"}
  end

  @doc """
  Returns the security schemes configured for an A2A server.
  Used to configure `A2A.Plug.Auth`.
  """
  @spec schemes_for_server(A2AServer.t()) :: map()
  def schemes_for_server(%A2AServer{auth_mode: :none}), do: %{}

  def schemes_for_server(%A2AServer{auth_mode: :bearer_token}) do
    %{"bearer" => %A2A.SecurityScheme.HTTPAuth{scheme: "bearer"}}
  end

  def schemes_for_server(%A2AServer{auth_mode: :api_key}) do
    %{"api_key" => %A2A.SecurityScheme.APIKey{name: "x-api-key", in: "header"}}
  end
end
