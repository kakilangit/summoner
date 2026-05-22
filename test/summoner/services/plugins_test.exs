defmodule Summoner.Services.PluginsTest do
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.PluginsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Services.Plugins

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{workspace: workspace}
  end

  describe "list_plugins/1" do
    test "returns empty list when no plugins", %{workspace: ws} do
      assert [] = Plugins.list_plugins(ws.id)
    end

    test "returns installed plugins", %{workspace: ws} do
      plugin_fixture(ws.id)
      assert [%{name: "grimoire-test"}] = Plugins.list_plugins(ws.id)
    end
  end

  describe "get_plugin!/2" do
    test "returns plugin by id", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert Plugins.get_plugin!(ws.id, plugin.id).name == "grimoire-test"
    end
  end

  describe "get_plugin/2" do
    test "returns plugin when found", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      found = Plugins.get_plugin(ws.id, plugin.id)
      assert found.id == plugin.id
    end
  end

  describe "list_plugins_paginated/2" do
    test "returns paginated results", %{workspace: ws} do
      plugin_fixture(ws.id)
      page = Plugins.list_plugins_paginated(ws.id, page: 1)
      assert length(page.entries) == 1
    end
  end

  describe "delete_plugin/1" do
    test "deletes the plugin", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert {:ok, _} = Plugins.delete_plugin(plugin)
      assert [] = Plugins.list_plugins(ws.id)
    end
  end
end
