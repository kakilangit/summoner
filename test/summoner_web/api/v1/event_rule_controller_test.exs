defmodule SummonerWeb.API.V1.EventRuleControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.AccessTokensFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Services.EventRules

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    token = access_token_fixture(workspace.id, workspace.tenant_id, %{scopes: ["api"]})

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token.token}")
      |> put_req_header("accept", "application/json")

    %{
      conn: conn,
      scope: scope,
      workspace: workspace
    }
  end

  defp create_event_rule(scope, workspace, attrs \\ %{}) do
    default = %{
      "name" => "test-rule-#{System.unique_integer([:positive])}",
      "event_type" => "invocation.completed",
      "action_type" => "send_notification",
      "action_config" => %{"channel" => "log"},
      "workspace_id" => workspace.id
    }

    {:ok, rule} = EventRules.create_rule(%{user: scope.user}, Map.merge(default, attrs))
    rule
  end

  describe "index" do
    test "lists event rules", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules")
      response = json_response(conn, 200)
      assert %{"items" => [%{"id" => id}], "meta" => meta} = response
      assert id == rule.id
      assert meta["page"] == 1
      assert meta["total_entries"] == 1
    end

    test "returns empty list when no rules", %{conn: conn, workspace: ws} do
      conn = get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules")
      assert %{"items" => [], "meta" => %{"total_entries" => 0}} = json_response(conn, 200)
    end

    test "returns 401 without token", %{workspace: ws} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules")

      assert json_response(conn, 401)
    end
  end

  describe "show" do
    test "returns event rule", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)

      conn =
        get(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/#{rule.id}")

      response = json_response(conn, 200)
      assert response["id"] == rule.id
      assert response["name"] == rule.name
      assert response["event_type"] == "invocation.completed"
      assert response["action_type"] == "send_notification"
    end
  end

  describe "create" do
    test "creates event rule with valid params", %{conn: conn, workspace: ws} do
      params = %{
        "name" => "my-rule",
        "event_type" => "invocation.completed",
        "action_type" => "send_notification",
        "action_config" => %{"channel" => "log"},
        "cooldown_s" => 60,
        "priority" => 50
      }

      conn =
        post(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules", params)

      response = json_response(conn, 201)
      assert response["name"] == "my-rule"
      assert response["event_type"] == "invocation.completed"
      assert response["cooldown_s"] == 60
      assert response["priority"] == 50
      assert response["enabled"] == true
    end

    test "returns validation error for missing name", %{conn: conn, workspace: ws} do
      params = %{
        "event_type" => "invocation.completed",
        "action_type" => "send_notification",
        "action_config" => %{}
      }

      conn =
        post(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules", params)

      assert json_response(conn, 422)
    end

    test "returns validation error for invalid event_type", %{conn: conn, workspace: ws} do
      params = %{
        "name" => "bad-rule",
        "event_type" => "invalid.type",
        "action_type" => "send_notification",
        "action_config" => %{}
      }

      conn =
        post(conn, ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules", params)

      assert json_response(conn, 422)
    end
  end

  describe "update" do
    test "updates event rule", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)

      conn =
        put(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/#{rule.id}",
          %{"name" => "updated-name"}
        )

      response = json_response(conn, 200)
      assert response["name"] == "updated-name"
    end

    test "toggles enabled", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)

      conn =
        put(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/#{rule.id}",
          %{"enabled" => false}
        )

      response = json_response(conn, 200)
      assert response["enabled"] == false
    end
  end

  describe "delete" do
    test "deletes event rule", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)

      conn =
        delete(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/#{rule.id}"
        )

      assert response(conn, 204)
    end
  end

  describe "test" do
    test "matches when conditions match", %{conn: conn, workspace: ws} do
      params = %{
        "conditions" => %{
          "field" => "status",
          "op" => "eq",
          "value" => "completed"
        },
        "event_data" => %{"status" => "completed"}
      }

      conn =
        post(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/test",
          params
        )

      assert %{"matches" => true} = json_response(conn, 200)
    end

    test "does not match when conditions don't match", %{conn: conn, workspace: ws} do
      params = %{
        "conditions" => %{
          "field" => "status",
          "op" => "eq",
          "value" => "failed"
        },
        "event_data" => %{"status" => "completed"}
      }

      conn =
        post(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/test",
          params
        )

      assert %{"matches" => false} = json_response(conn, 200)
    end
  end

  describe "executions" do
    test "lists executions for a rule", %{conn: conn, scope: scope, workspace: ws} do
      rule = create_event_rule(scope, ws)

      conn =
        get(
          conn,
          ~p"/api/v1/tenants/#{ws.tenant_id}/workspaces/#{ws.id}/event-rules/#{rule.id}/executions"
        )

      response = json_response(conn, 200)
      assert %{"items" => [], "meta" => %{"total_entries" => 0}} = response
    end
  end
end
