defmodule SummonerWeb.API.V1.AgentControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{
      conn: conn,
      scope: scope,
      workspace: workspace,
      provider: provider,
      token: token
    }
  end

  describe "index" do
    test "lists agents", %{conn: conn, scope: scope, workspace: ws, provider: provider} do
      agent = agent_fixture(scope, ws.id, provider.id)
      conn = get(conn, ~p"/api/v1/agents")
      assert %{"data" => [%{"id" => id, "name" => name}]} = json_response(conn, 200)
      assert id == agent.id
      assert name == agent.name
    end

    test "returns empty list when no agents", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agents")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns 401 without token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/agents")

      assert json_response(conn, 401)["error"]["code"] == "missing_token"
    end

    test "returns 401 with invalid token" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer shk_invalid")
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/agents")

      assert json_response(conn, 401)["error"]["code"] == "invalid_token"
    end

    test "returns 403 with wrong scope", %{workspace: ws} do
      token = access_token_fixture(ws.id, ws.tenant_id, %{scopes: ["a2a"]})

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.token}")
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/agents")

      assert json_response(conn, 403)["error"]["code"] == "insufficient_scope"
    end
  end

  describe "show" do
    test "returns agent with details", %{
      conn: conn,
      scope: scope,
      workspace: ws,
      provider: provider
    } do
      agent = agent_fixture(scope, ws.id, provider.id)
      conn = get(conn, ~p"/api/v1/agents/#{agent.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == agent.id
      assert data["type"] == "local"
      assert data["local_agent"]["model"] == "test-model"
      assert data["local_agent"]["provider_id"] == provider.id
    end
  end

  describe "create" do
    test "creates local agent", %{conn: conn, provider: provider} do
      attrs = %{
        "name" => "New Agent",
        "role" => "autonomous",
        "model" => "test-model",
        "provider_id" => provider.id
      }

      conn = post(conn, ~p"/api/v1/agents", agent: attrs)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "New Agent"
      assert data["type"] == "local"
      assert data["local_agent"]["model"] == "test-model"
    end

    test "returns 422 with invalid attrs", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/agents", agent: %{"name" => ""})
      assert json_response(conn, 422)["error"]["code"] == "validation_error"
    end
  end

  describe "update" do
    test "updates agent name", %{conn: conn, scope: scope, workspace: ws, provider: provider} do
      agent = agent_fixture(scope, ws.id, provider.id)
      conn = patch(conn, ~p"/api/v1/agents/#{agent.id}", agent: %{"name" => "Updated"})
      assert %{"data" => %{"name" => "Updated"}} = json_response(conn, 200)
    end
  end

  describe "delete" do
    test "soft-deletes agent", %{conn: conn, scope: scope, workspace: ws, provider: provider} do
      agent = agent_fixture(scope, ws.id, provider.id)
      conn = delete(conn, ~p"/api/v1/agents/#{agent.id}")
      assert response(conn, 204)
    end
  end
end
