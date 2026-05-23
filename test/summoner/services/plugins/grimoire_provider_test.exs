defmodule Summoner.Services.Plugins.GrimoireProviderTest do
  use Summoner.DataCase

  import Summoner.Adapters.Persistence.AccountsFixtures
  import Summoner.Adapters.Persistence.PluginsFixtures
  import Summoner.Adapters.Persistence.WorkspacesFixtures

  alias Summoner.Ports.Persistence.Providers
  alias Summoner.Services.Plugins

  setup do
    scope = user_scope_fixture()
    workspace = workspace_fixture(scope)
    %{workspace: workspace}
  end

  describe "provider auto-registration" do
    test "creates grimoire provider when enabling plugin with provider capability", %{
      workspace: ws
    } do
      plugin =
        plugin_fixture(ws.id, %{
          capabilities: ["provider"],
          manifest: valid_manifest(%{"capabilities" => ["provider"]})
        })

      # Simulate enable without container (just test provider creation)
      Plugins.maybe_register_provider(plugin)

      provider = Providers.find_by_plugin_installation(plugin.id)
      assert provider != nil
      assert provider.kind == "grimoire"
      assert provider.api_format == :grimoire
      assert provider.type == :local
      assert provider.status == :online
      assert provider.name == "grimoire:#{plugin.name}"
      assert provider.workspace_id == ws.id
      assert provider.plugin_installation_id == plugin.id
    end

    test "does not create provider for plugin without provider capability", %{workspace: ws} do
      plugin =
        plugin_fixture(ws.id, %{
          capabilities: ["tools"],
          manifest: valid_manifest(%{"capabilities" => ["tools"]})
        })

      Plugins.maybe_register_provider(plugin)

      assert Providers.find_by_plugin_installation(plugin.id) == nil
    end

    test "reactivates existing provider on re-enable", %{workspace: ws} do
      plugin =
        plugin_fixture(ws.id, %{
          capabilities: ["provider"],
          manifest: valid_manifest(%{"capabilities" => ["provider"]})
        })

      # Register then deactivate
      Plugins.maybe_register_provider(plugin)
      Plugins.maybe_deactivate_provider(plugin)

      provider = Providers.find_by_plugin_installation(plugin.id)
      assert provider.status == :offline

      # Re-enable
      Plugins.maybe_register_provider(plugin)

      provider = Providers.find_by_plugin_installation(plugin.id)
      assert provider.status == :online
    end

    test "deactivates provider on disable", %{workspace: ws} do
      plugin =
        plugin_fixture(ws.id, %{
          capabilities: ["provider"],
          manifest: valid_manifest(%{"capabilities" => ["provider"]})
        })

      Plugins.maybe_register_provider(plugin)
      Plugins.maybe_deactivate_provider(plugin)

      provider = Providers.find_by_plugin_installation(plugin.id)
      assert provider.status == :offline
    end
  end
end
