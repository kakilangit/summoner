defmodule SummonerWeb.API.V1.AdminControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)

    admin_token =
      access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["admin"]})

    api_token =
      access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    admin_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{admin_token.token}")
      |> put_req_header("accept", "application/json")

    api_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{api_token.token}")
      |> put_req_header("accept", "application/json")

    %{admin_conn: admin_conn, api_conn: api_conn, scope: scope, workspace: workspace}
  end

  describe "list_tenants" do
    test "returns tenants with admin scope", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/tenants")
      assert %{"items" => tenants} = json_response(conn, 200)
      assert is_list(tenants)
    end

    test "returns 403 with api scope (not admin)", %{api_conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/tenants")
      assert json_response(conn, 403)["error"]["code"] == "insufficient_scope"
    end
  end

  describe "list_users" do
    test "returns users with admin scope", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/users")
      assert %{"items" => users} = json_response(conn, 200)
      assert is_list(users)
      assert users != []
    end
  end

  describe "update_user" do
    test "disables a user", %{admin_conn: conn, scope: scope} do
      conn = patch(conn, ~p"/api/v1/admin/users/#{scope.user.id}", %{action: "disable"})
      user = json_response(conn, 200)
      assert user["id"] == scope.user.id
    end

    test "enables a user", %{admin_conn: conn, scope: scope} do
      conn = patch(conn, ~p"/api/v1/admin/users/#{scope.user.id}", %{action: "enable"})
      user = json_response(conn, 200)
      assert user["id"] == scope.user.id
    end

    test "returns 400 for invalid action", %{admin_conn: conn, scope: scope} do
      conn = patch(conn, ~p"/api/v1/admin/users/#{scope.user.id}", %{})
      assert json_response(conn, 400)["error"]["code"] == "bad_request"
    end

    test "rejects non-admin token", %{api_conn: conn, scope: scope} do
      conn = patch(conn, ~p"/api/v1/admin/users/#{scope.user.id}", %{action: "disable"})
      assert json_response(conn, 403)["error"]["code"] == "insufficient_scope"
    end
  end

  describe "list_invitations" do
    test "returns invitations with admin scope", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/invitations")
      assert %{"items" => invitations} = json_response(conn, 200)
      assert is_list(invitations)
    end
  end

  describe "stats" do
    test "returns system stats with admin scope", %{admin_conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/stats")
      stats = json_response(conn, 200)
      assert is_integer(stats["user_count"])
      assert is_integer(stats["tenant_count"])
    end
  end
end
