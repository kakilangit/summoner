defmodule SummonerWeb.API.V1.InvocationControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures
  import Summoner.Adapters.Persistence.OrchestrationFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    provider = provider_fixture(scope, workspace.id)
    agent = agent_fixture(scope, workspace.id, provider.id)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    invocation =
      invocation_fixture(scope, workspace.id, agent.id, %{
        status: :completed,
        output: %{"summary" => "done"}
      })

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{
      conn: conn,
      scope: scope,
      workspace: workspace,
      agent: agent,
      invocation: invocation
    }
  end

  describe "show" do
    test "returns invocation details", %{conn: conn, invocation: inv} do
      conn = get(conn, ~p"/api/v1/invocations/#{inv.id}")
      data = json_response(conn, 200)
      assert data["id"] == inv.id
      assert data["status"] == "completed"
    end
  end

  describe "steps" do
    test "returns empty steps for invocation", %{conn: conn, invocation: inv} do
      conn = get(conn, ~p"/api/v1/invocations/#{inv.id}/steps")
      assert %{"items" => []} = json_response(conn, 200)
    end
  end

  describe "events" do
    test "returns empty events for invocation", %{conn: conn, invocation: inv} do
      conn = get(conn, ~p"/api/v1/invocations/#{inv.id}/events")
      assert %{"items" => []} = json_response(conn, 200)
    end
  end

  describe "cancel" do
    test "returns 202 accepted", %{conn: conn, invocation: inv} do
      conn = post(conn, ~p"/api/v1/invocations/#{inv.id}/cancel")
      assert response(conn, 202)
    end
  end

  describe "auth" do
    test "returns 401 without token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/invocations/#{Nulid.generate() |> elem(1)}")

      assert json_response(conn, 401)["error"]["code"] == "missing_token"
    end
  end
end
