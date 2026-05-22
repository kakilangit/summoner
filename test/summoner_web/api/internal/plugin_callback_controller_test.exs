defmodule SummonerWeb.API.Internal.PluginCallbackControllerTest do
  use SummonerWeb.ConnCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.PluginsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  setup %{conn: conn} do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    container = plugin_container_fixture()

    plugin =
      plugin_fixture(workspace.id, %{
        status: :enabled,
        digest: container.digest,
        capabilities: ["tools", "events"]
      })

    conn =
      conn
      |> put_req_header("x-plugin-token", container.callback_token)
      |> put_req_header("x-workspace-id", workspace.id)
      |> put_req_header("x-plugin-id", plugin.id)

    %{conn: conn, workspace: workspace, plugin: plugin, container: container}
  end

  describe "callback/2" do
    test "returns 401 without plugin token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("x-plugin-token")
        |> post(~p"/api/internal/plugins/callback", %{})

      assert json_response(conn, 401)["error"] =~ "Invalid"
    end

    test "returns 400 with missing action field", %{conn: conn} do
      conn = post(conn, ~p"/api/internal/plugins/callback", %{"params" => %{}})

      assert json_response(conn, 400)["error"] =~ "Missing"
    end

    test "returns 400 without workspace header", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("x-workspace-id")
        |> post(~p"/api/internal/plugins/callback", %{
          "action" => "log",
          "params" => %{"level" => "info", "message" => "test"}
        })

      assert json_response(conn, 400)["ok"] == false
    end

    test "handles log action", %{conn: conn} do
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "log",
          "params" => %{"level" => "info", "message" => "hello"}
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
    end

    test "handles emit_event action", %{conn: conn} do
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "emit_event",
          "params" => %{"event" => "test_event", "data" => %{"key" => "value"}}
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
    end

    test "handles set_state action", %{conn: conn} do
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "set_state",
          "params" => %{"key" => "my_key", "value" => %{"data" => "hello"}}
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
    end

    test "handles get_state action after set", %{conn: conn} do
      # Set state first
      post(conn, ~p"/api/internal/plugins/callback", %{
        "action" => "set_state",
        "params" => %{"key" => "my_key", "value" => %{"data" => "hello"}}
      })

      # Get state
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "get_state",
          "params" => %{"key" => "my_key"}
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert resp["result"]["key"] == "my_key"
      assert resp["result"]["value"] == %{"data" => "hello"}
    end

    test "handles delete_state action", %{conn: conn} do
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "delete_state",
          "params" => %{"key" => "nonexistent"}
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
    end

    test "returns 422 for unsupported action type", %{conn: conn} do
      conn =
        post(conn, ~p"/api/internal/plugins/callback", %{
          "action" => "unknown_action",
          "params" => %{}
        })

      assert json_response(conn, 422)["error"] =~ "Unsupported"
    end
  end
end
