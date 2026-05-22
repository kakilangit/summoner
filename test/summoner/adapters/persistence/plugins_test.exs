defmodule Summoner.Adapters.Persistence.PluginsTest do
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.PluginsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Ports.Persistence.Plugins

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{workspace: workspace}
  end

  describe "create_plugin/2" do
    test "creates with valid attrs", %{workspace: ws} do
      assert {:ok, plugin} = Plugins.create_plugin(ws.id, valid_plugin_attrs())
      assert plugin.name == "grimoire-test"
      assert plugin.status == :installed
      assert plugin.capabilities == ["tools"]
    end

    test "rejects duplicate name in same workspace", %{workspace: ws} do
      plugin_fixture(ws.id)
      assert {:error, changeset} = Plugins.create_plugin(ws.id, valid_plugin_attrs())
      assert errors_on(changeset)[:name] || errors_on(changeset)[:workspace_id]
    end
  end

  describe "get_plugin!/2" do
    test "returns plugin", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert Plugins.get_plugin!(ws.id, plugin.id).id == plugin.id
    end
  end

  describe "get_plugin_by_name/2" do
    test "returns plugin by name", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert Plugins.get_plugin_by_name(ws.id, plugin.name).id == plugin.id
    end

    test "returns nil for missing name", %{workspace: ws} do
      assert is_nil(Plugins.get_plugin_by_name(ws.id, "nope"))
    end
  end

  describe "list_plugins/1" do
    test "lists plugins in workspace", %{workspace: ws} do
      plugin_fixture(ws.id)
      assert [_] = Plugins.list_plugins(ws.id)
    end

    test "returns empty for no plugins", %{workspace: ws} do
      assert [] = Plugins.list_plugins(ws.id)
    end
  end

  describe "update_status/3" do
    test "transitions status", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert {:ok, updated} = Plugins.update_status(plugin, :enabled)
      assert updated.status == :enabled
    end

    test "sets error message on error status", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert {:ok, updated} = Plugins.update_status(plugin, :error, "container crashed")
      assert updated.status == :error
      assert updated.error_message == "container crashed"
    end
  end

  describe "delete_plugin/1" do
    test "deletes plugin", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      assert {:ok, _} = Plugins.delete_plugin(plugin)
      assert is_nil(Plugins.get_plugin(ws.id, plugin.id))
    end
  end

  describe "list_enabled_by_capability/2" do
    test "returns only enabled plugins with matching capability", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      Plugins.update_status(plugin, :enabled)

      assert [found] = Plugins.list_enabled_by_capability(ws.id, "tools")
      assert found.id == plugin.id
    end

    test "excludes disabled plugins", %{workspace: ws} do
      plugin_fixture(ws.id)
      assert [] = Plugins.list_enabled_by_capability(ws.id, "tools")
    end

    test "excludes wrong capability", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)
      Plugins.update_status(plugin, :enabled)

      assert [] = Plugins.list_enabled_by_capability(ws.id, "webhooks")
    end
  end

  describe "conversation mapping" do
    test "upsert creates and updates", %{workspace: ws} do
      plugin = plugin_fixture(ws.id)

      # Need a conversation for FK
      scope = user_scope_fixture()
      workspace2 = workspace_fixture(scope)

      import Summoner.Adapters.Persistence.AgentsFixtures
      import Summoner.Adapters.Persistence.ProvidersFixtures

      provider = provider_fixture(scope, workspace2.id)
      agent = agent_fixture(scope, workspace2.id, provider.id)

      import Summoner.Adapters.Persistence.ConversationsFixtures

      conversation = conversation_fixture(scope, workspace2.id, agent.id)

      attrs = %{
        plugin_id: plugin.id,
        external_ref: "C123:ts456",
        conversation_id: conversation.id
      }

      assert {:ok, pc} = Plugins.upsert_conversation(attrs)
      assert pc.external_ref == "C123:ts456"

      # Lookup
      assert found = Plugins.get_conversation_by_ref(plugin.id, "C123:ts456")
      assert found.id == pc.id

      # Missing ref
      assert is_nil(Plugins.get_conversation_by_ref(plugin.id, "nope"))
    end
  end
end
