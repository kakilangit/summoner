defmodule SummonerWeb.A2AEndpoint do
  @moduledoc """
  Plug that routes inbound A2A requests to the correct AgentBridge.

  Mounted at `/summons/:agent_id` in the router. Resolves the
  A2A server from agent_id, ensures the bridge GenServer is
  running, configures auth and base_url, then delegates to `A2A.Plug`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Summoner.A2A, as: SummonerA2A
  alias Summoner.A2A.AgentBridge
  alias Summoner.A2A.Auth

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.path_info do
      [agent_id | rest] ->
        conn = %{conn | path_info: rest}
        dispatch(conn, agent_id)

      _ ->
        conn |> send_resp(404, "Not Found") |> halt()
    end
  end

  defp dispatch(conn, agent_id) do
    with {:ok, a2a_server} <- lookup_server(agent_id),
         {:ok, bridge_pid} <- AgentBridge.ensure_started(a2a_server.id) do
      conn
      |> put_private(:a2a_server, a2a_server)
      |> maybe_auth(a2a_server)
      |> maybe_halted(a2a_server, bridge_pid)
    else
      {:error, :not_found} ->
        conn |> send_resp(404, "Agent not found") |> halt()

      {:error, reason} ->
        conn |> send_resp(503, "Service unavailable: #{inspect(reason)}") |> halt()
    end
  end

  defp lookup_server(agent_id) do
    server = SummonerA2A.get_enabled_server_by_agent_id!(agent_id)
    {:ok, server}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp maybe_auth(conn, a2a_server) do
    schemes = Auth.schemes_for_server(a2a_server)

    if schemes == %{} do
      conn
    else
      auth_opts =
        A2A.Plug.Auth.init(
          schemes: schemes,
          verify: &Auth.verify/3,
          exempt_paths: [[".well-known", "agent-card.json"]]
        )

      A2A.Plug.Auth.call(conn, auth_opts)
    end
  end

  defp maybe_halted(%{halted: true} = conn, _server, _pid), do: conn

  defp maybe_halted(conn, a2a_server, bridge_pid) do
    base_url = SummonerA2A.base_url(a2a_server)

    plug_opts =
      A2A.Plug.init(
        agent: bridge_pid,
        base_url: base_url,
        agent_card_path: [".well-known", "agent-card.json"],
        json_rpc_path: [],
        metadata: %{
          "server_id" => a2a_server.id,
          "workspace_id" => a2a_server.workspace_id
        }
      )

    A2A.Plug.call(conn, plug_opts)
  end
end
