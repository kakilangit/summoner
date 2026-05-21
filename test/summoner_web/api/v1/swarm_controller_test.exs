defmodule SummonerWeb.API.V1.SwarmControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.SwarmsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{conn: conn, scope: scope, workspace: workspace, agent: agent}
  end

  describe "index" do
    test "lists swarms", %{conn: conn, scope: scope, workspace: ws} do
      swarm = swarm_fixture(scope, ws.id)
      conn = get(conn, ~p"/api/v1/swarms")
      assert %{"data" => [%{"id" => id}]} = json_response(conn, 200)
      assert id == swarm.id
    end
  end

  describe "show" do
    test "returns swarm with members", %{conn: conn, scope: scope, workspace: ws} do
      swarm = swarm_fixture(scope, ws.id)
      conn = get(conn, ~p"/api/v1/swarms/#{swarm.id}")
      assert %{"data" => %{"id" => id, "members" => members}} = json_response(conn, 200)
      assert id == swarm.id
      assert is_list(members)
    end
  end

  describe "create" do
    test "creates swarm", %{conn: conn, agent: agent} do
      attrs = %{"name" => "Test Party", "mode" => "relay", "coordinator_agent_id" => agent.id}
      conn = post(conn, ~p"/api/v1/swarms", swarm: attrs)
      assert %{"data" => %{"name" => "Test Party"}} = json_response(conn, 201)
    end
  end

  describe "delete" do
    test "deletes swarm", %{conn: conn, scope: scope, workspace: ws} do
      swarm = swarm_fixture(scope, ws.id)
      conn = delete(conn, ~p"/api/v1/swarms/#{swarm.id}")
      assert response(conn, 204)
    end
  end
end
