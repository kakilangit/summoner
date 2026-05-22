defmodule SummonerWeb.API.V1.ConversationControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ConversationsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
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
    test "lists conversations", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      conv = conversation_fixture(scope, ws.id, agent.id)
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/conversations")
      assert %{"items" => [%{"id" => id}]} = json_response(conn, 200)
      assert id == conv.id
    end
  end

  describe "show" do
    test "returns conversation", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      conv = conversation_fixture(scope, ws.id, agent.id)

      conn =
        get(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/conversations/#{conv.id}"
        )

      assert %{"id" => id, "kind" => "chat"} = json_response(conn, 200)
      assert id == conv.id
    end
  end

  describe "create" do
    test "creates conversation", %{conn: conn, workspace: ws, agent: agent} do
      attrs = %{"title" => "Test Chat", "primary_agent_id" => agent.id}

      conn =
        post(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/conversations", attrs)

      assert %{"title" => "Test Chat"} = json_response(conn, 201)
    end
  end

  describe "delete" do
    test "deletes conversation", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      conv = conversation_fixture(scope, ws.id, agent.id)

      conn =
        delete(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/conversations/#{conv.id}"
        )

      assert response(conn, 204)
    end
  end

  describe "messages" do
    test "lists messages for conversation", %{
      conn: conn,
      scope: scope,
      workspace: ws,
      agent: agent
    } do
      conv = conversation_fixture(scope, ws.id, agent.id)

      conn =
        get(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/conversations/#{conv.id}/messages"
        )

      assert %{"items" => messages} = json_response(conn, 200)
      assert is_list(messages)
    end
  end
end
