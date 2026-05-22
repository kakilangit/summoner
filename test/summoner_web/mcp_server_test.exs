defmodule SummonerWeb.MCPServerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    # Start the MCP server for each test
    start_supervised!({Summoner.Adapters.MCP.Server, transport: {:streamable_http, start: true}})

    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)

    token =
      access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    %{workspace: workspace, token: token}
  end

  defp mcp_init(token) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")
      |> post("/mcp", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "test-client", "version" => "1.0"}
        }
      })

    session_id = get_resp_header(conn, "mcp-session-id") |> List.first()
    {conn, session_id}
  end

  defp mcp_request(token, session_id, id, method, params \\ %{}) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token.token}")
    |> put_req_header("accept", "application/json")
    |> put_req_header("mcp-session-id", session_id)
    |> post("/mcp", %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    })
  end

  describe "MCP auth plug" do
    test "rejects invalid bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> put_req_header("accept", "application/json")
        |> post("/mcp", %{})

      assert json_response(conn, 401)["error"]["code"] == "unauthorized"
    end
  end

  describe "MCP initialize" do
    test "accepts valid bearer token and returns server info", %{token: token} do
      {conn, _session_id} = mcp_init(token)

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["result"]["serverInfo"]["name"] == "summoner"
      assert is_map(body["result"]["capabilities"])
    end
  end

  describe "MCP tools/list" do
    test "lists all registered tools", %{token: token} do
      {_init_conn, session_id} = mcp_init(token)

      # Send initialized notification
      mcp_request(token, session_id, nil, "notifications/initialized")

      conn = mcp_request(token, session_id, 2, "tools/list")

      assert conn.status == 200
      body = json_response(conn, 200)
      tools = body["result"]["tools"]
      assert is_list(tools)

      tool_names = Enum.map(tools, & &1["name"])
      assert "invoke_agent" in tool_names
      assert "list_agents" in tool_names
      assert "run_pipeline" in tool_names
      assert "list_pipelines" in tool_names
      assert "search_skills" in tool_names
    end
  end
end
