defmodule SummonerWeb.API.V1.UsageControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{conn: conn, workspace: workspace}
  end

  describe "index" do
    test "returns usage summary", %{conn: conn, workspace: ws} do
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/usages")
      data = json_response(conn, 200)
      assert is_integer(data["rolling_30_day_tokens"]) or is_nil(data["rolling_30_day_tokens"])
    end
  end

  describe "breakdowns" do
    test "returns breakdown by agent, model, provider", %{conn: conn, workspace: ws} do
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/usages/breakdowns")
      data = json_response(conn, 200)
      assert is_list(data["by_agent"])
      assert is_list(data["by_model"])
      assert is_list(data["by_provider"])
    end
  end

  describe "auth" do
    test "returns 401 without token", %{workspace: ws} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/usages")

      assert json_response(conn, 401)["error"]["code"] == "missing_token"
    end
  end
end
