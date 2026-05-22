defmodule SummonerWeb.API.V1.ProviderControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{conn: conn, scope: scope, workspace: workspace}
  end

  describe "index" do
    test "lists providers", %{conn: conn, scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/providers")
      assert %{"items" => [%{"id" => id}]} = json_response(conn, 200)
      assert id == provider.id
    end
  end

  describe "show" do
    test "returns provider", %{conn: conn, scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)

      conn =
        get(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/providers/#{provider.id}"
        )

      assert %{"id" => id, "kind" => "ollama"} = json_response(conn, 200)
      assert id == provider.id
    end
  end

  describe "create" do
    test "creates provider", %{conn: conn, workspace: ws} do
      attrs = %{
        "name" => "New Provider",
        "kind" => "ollama",
        "api_format" => "openai",
        "type" => "local",
        "base_url" => "http://localhost:11434"
      }

      conn = post(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/providers", attrs)
      assert %{"name" => "New Provider"} = json_response(conn, 201)
    end
  end

  describe "delete" do
    test "deletes provider", %{conn: conn, scope: scope, workspace: ws} do
      provider = provider_fixture(scope, ws.id)

      conn =
        delete(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/providers/#{provider.id}"
        )

      assert response(conn, 204)
    end
  end
end
