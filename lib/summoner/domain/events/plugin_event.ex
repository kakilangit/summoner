defmodule Summoner.Domain.Events.PluginEvent do
  @moduledoc "Domain event emitted by plugins via emit_event action."

  @enforce_keys [:plugin_id, :plugin_name, :event_name, :data, :workspace_id]
  defstruct [:plugin_id, :plugin_name, :event_name, :data, :workspace_id]
end
