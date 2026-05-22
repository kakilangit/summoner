defmodule SummonerWeb.Plugs.PluginCallbackAuthTest do
  use Summoner.DataCase

  import Plug.Conn
  import Summoner.Adapters.Persistence.PluginsFixtures

  alias SummonerWeb.Plugs.PluginCallbackAuth

  setup do
    container = plugin_container_fixture()
    %{container: container}
  end

  defp build_conn(token) do
    :post
    |> Plug.Test.conn("/api/internal/plugins/callback")
    |> put_req_header("x-plugin-token", token)
    |> put_req_header("content-type", "application/json")
  end

  test "assigns plugin_container on valid token", %{container: container} do
    conn =
      container.callback_token
      |> build_conn()
      |> PluginCallbackAuth.call(PluginCallbackAuth.init([]))

    assert conn.assigns[:plugin_container].id == container.id
    refute conn.halted
  end

  test "returns 401 when no X-Plugin-Token header" do
    conn =
      :post
      |> Plug.Test.conn("/api/internal/plugins/callback")
      |> put_req_header("content-type", "application/json")
      |> PluginCallbackAuth.call(PluginCallbackAuth.init([]))

    assert conn.status == 401
    assert conn.halted
  end

  test "returns 401 for invalid token" do
    conn =
      "invalid-token"
      |> build_conn()
      |> PluginCallbackAuth.call(PluginCallbackAuth.init([]))

    assert conn.status == 401
    assert conn.halted
  end

  test "returns 401 for stopped container token" do
    container = plugin_container_fixture(%{status: :stopped})

    conn =
      container.callback_token
      |> build_conn()
      |> PluginCallbackAuth.call(PluginCallbackAuth.init([]))

    assert conn.status == 401
    assert conn.halted
  end
end
