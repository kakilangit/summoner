defmodule Summoner.Adapters.Persistence.PluginsFixtures do
  @moduledoc "Fixtures for plugin tests."

  alias Summoner.Ports.Persistence.Plugins

  def valid_manifest(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "grimoire-test",
        "version" => "1.0.0",
        "image" => "ghcr.io/summoner/grimoire-test:1.0.0",
        "capabilities" => ["tools"],
        "description" => "A test plugin"
      },
      overrides
    )
  end

  def valid_plugin_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        name: "grimoire-test",
        version: "1.0.0",
        capabilities: ["tools"],
        manifest: valid_manifest()
      },
      attrs
    )
  end

  def plugin_fixture(workspace_id, attrs \\ %{}) do
    attrs = valid_plugin_attrs(attrs)
    {:ok, plugin} = Plugins.create_plugin(workspace_id, attrs)
    plugin
  end
end
