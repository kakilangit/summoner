defmodule SummonerWeb.API.V1.WebhookControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.AgentsFixtures
  import Summoner.Adapters.Persistence.ProvidersFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Ports.Persistence.Webhooks

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

    %{
      conn: conn,
      scope: scope,
      workspace: workspace,
      agent: agent
    }
  end

  defp create_webhook(scope, workspace, agent, attrs \\ %{}) do
    default = %{
      "name" => "test-webhook-#{System.unique_integer([:positive])}",
      "target_type" => "agent",
      "target_id" => agent.id,
      "auth_mode" => "public",
      "response_mode" => "async",
      "workspace_id" => workspace.id
    }

    {:ok, webhook} = Webhooks.create_webhook(%{user: scope.user}, Map.merge(default, attrs))
    webhook
  end

  describe "index" do
    test "lists webhooks", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      webhook = create_webhook(scope, ws, agent)
      conn = get(conn, ~p"/api/v1/webhooks")
      response = json_response(conn, 200)
      assert %{"items" => [%{"id" => id}], "meta" => meta} = response
      assert id == webhook.id
      assert meta["page"] == 1
      assert meta["total_entries"] == 1
    end

    test "returns empty list when no webhooks", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/webhooks")
      assert %{"items" => [], "meta" => %{"total_entries" => 0}} = json_response(conn, 200)
    end

    test "returns 401 without token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/webhooks")

      assert json_response(conn, 401)
    end
  end

  describe "show" do
    test "returns webhook", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      webhook = create_webhook(scope, ws, agent)
      conn = get(conn, ~p"/api/v1/webhooks/#{webhook.id}")
      response = json_response(conn, 200)
      assert response["id"] == webhook.id
      assert response["name"] == webhook.name
      assert response["target_type"] == "agent"
      assert response["auth_mode"] == "public"
    end
  end

  describe "create" do
    test "creates webhook with valid params", %{conn: conn, agent: agent} do
      params = %{
        "name" => "my-webhook",
        "target_type" => "agent",
        "target_id" => agent.id,
        "auth_mode" => "public",
        "response_mode" => "async"
      }

      conn = post(conn, ~p"/api/v1/webhooks", params)
      response = json_response(conn, 201)
      assert response["name"] == "my-webhook"
      assert response["target_type"] == "agent"
      assert response["auth_mode"] == "public"
      assert response["response_mode"] == "async"
      assert response["enabled"] == true
    end

    test "returns validation error for missing name", %{conn: conn, agent: agent} do
      params = %{"target_type" => "agent", "target_id" => agent.id}
      conn = post(conn, ~p"/api/v1/webhooks", params)
      assert json_response(conn, 422)
    end
  end

  describe "update" do
    test "updates webhook", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      webhook = create_webhook(scope, ws, agent)
      conn = put(conn, ~p"/api/v1/webhooks/#{webhook.id}", %{"name" => "updated-name"})
      response = json_response(conn, 200)
      assert response["name"] == "updated-name"
    end

    test "updates enabled flag", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      webhook = create_webhook(scope, ws, agent)
      conn = put(conn, ~p"/api/v1/webhooks/#{webhook.id}", %{"enabled" => false})
      response = json_response(conn, 200)
      assert response["enabled"] == false
    end
  end

  describe "delete" do
    test "deletes webhook", %{conn: conn, scope: scope, workspace: ws, agent: agent} do
      webhook = create_webhook(scope, ws, agent)
      conn = delete(conn, ~p"/api/v1/webhooks/#{webhook.id}")
      assert response(conn, 204)
    end
  end
end
