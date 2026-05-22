defmodule Summoner.Adapters.Persistence.PluginsFixtures do
  @moduledoc "Fixtures for plugin tests."

  alias Summoner.Domain.Schemas.PluginContainer
  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Repo

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
        manifest: valid_manifest(),
        ref: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower),
        digest: "sha256:#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
        trusted: true
      },
      attrs
    )
  end

  def plugin_fixture(workspace_id, attrs \\ %{}) do
    attrs = valid_plugin_attrs(attrs)
    {:ok, plugin} = Plugins.create_plugin(workspace_id, attrs)
    plugin
  end

  def plugin_container_fixture(attrs \\ %{}) do
    defaults = %{
      image: "ghcr.io/summoner/grimoire-test:1.0.0",
      digest: "sha256:#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
      container_id: "docker-#{System.unique_integer([:positive])}",
      container_name: "summoner-plugin-test-#{System.unique_integer([:positive])}",
      host: "localhost",
      port: 9999,
      status: :running,
      callback_token: "test-token-#{System.unique_integer([:positive])}"
    }

    attrs = Map.merge(defaults, attrs)

    %PluginContainer{}
    |> PluginContainer.changeset(attrs)
    |> Repo.insert!()
  end
end
