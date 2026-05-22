defmodule Summoner.Ports.Persistence.Plugins do
  @moduledoc "Port for plugin persistence operations."

  @adapter Application.compile_env(
             :summoner,
             [:persistence_adapters, :plugins],
             Summoner.Adapters.Persistence.Plugins
           )

  defdelegate create_plugin(workspace_id, attrs), to: @adapter
  defdelegate get_plugin!(workspace_id, id), to: @adapter
  defdelegate get_plugin(workspace_id, id), to: @adapter
  defdelegate get_plugin_by_name(workspace_id, name), to: @adapter
  defdelegate get_plugin_by_ref!(workspace_id, ref), to: @adapter
  defdelegate list_plugins(workspace_id), to: @adapter
  defdelegate list_plugins_paginated(workspace_id, opts), to: @adapter
  defdelegate update_plugin(plugin, attrs), to: @adapter
  defdelegate update_status(plugin, status, error_message \\ nil), to: @adapter
  defdelegate delete_plugin(plugin), to: @adapter
  defdelegate list_enabled_by_capability(workspace_id, capability), to: @adapter
  defdelegate upsert_conversation(attrs), to: @adapter
  defdelegate get_conversation_by_ref(plugin_id, external_ref), to: @adapter

  # Plugin state
  defdelegate get_state(workspace_id, plugin_id, key), to: @adapter
  defdelegate set_state(attrs), to: @adapter
  defdelegate delete_state(workspace_id, plugin_id, key), to: @adapter

  # Container support
  defdelegate enabled_digests(), to: @adapter
end
