defmodule Summoner.Services.A2A.Auth do
  @moduledoc """
  Authentication verification for A2A inbound requests.

  Implements the `verify/3` callback used by `A2A.Plug.Auth` to validate
  credentials against the A2A server's token system.
  """

  alias Summoner.Ports.Persistence.A2A, as: SummonerA2A
  alias Summoner.Domain.Schemas.A2AServer

  @doc """
  Verifies a credential extracted by `A2A.Plug.Auth`.

  Returns `{:ok, identity}` on success or `{:error, reason}` on failure.
  The identity map is stored in `conn.private[:a2a][:auth]`.
  """
  @spec verify(String.t(), String.t(), Plug.Conn.t()) ::
          {:ok, map()} | {:error, String.t()}
  def verify(_scheme_name, credential, conn) do
    a2a_server = conn.private[:a2a_server]

    if a2a_server do
      case SummonerA2A.verify_token(a2a_server.workspace_id, credential) do
        {:ok, token} ->
          {:ok,
           %{
             server_id: a2a_server.id,
             workspace_id: a2a_server.workspace_id,
             token_id: token.id
           }}

        {:error, :invalid} ->
          {:error, "Invalid token"}
      end
    else
      {:error, "No A2A server context"}
    end
  end

  @doc """
  Returns the security schemes for an A2A server based on access mode.
  """
  @spec schemes_for_server(A2AServer.t()) :: map()
  def schemes_for_server(%A2AServer{access_mode: :public}), do: %{}

  def schemes_for_server(%A2AServer{access_mode: :protected}) do
    %{"bearer" => %A2A.SecurityScheme.HTTPAuth{scheme: "bearer"}}
  end
end
