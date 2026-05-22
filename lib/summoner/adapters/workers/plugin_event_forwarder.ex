defmodule Summoner.Adapters.Workers.PluginEventForwarder do
  @moduledoc """
  GenServer that subscribes to global PubSub and forwards domain events
  to enabled plugin containers with `events` capability.

  Uses `PluginClient` (HTTP) to forward events. Actions returned in
  responses are no longer supported — plugins use the callback API instead.
  """

  use GenServer

  alias Summoner.Adapters.Workers.PluginContainerManager
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Plugins, as: PluginsService
  alias Summoner.Services.Plugins.EventSerializer
  alias Summoner.Services.Plugins.PluginClient
  alias Summoner.Services.Plugins.TrustVerifier

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Events.subscribe(:global)
    {:ok, %{}}
  end

  @impl true
  def handle_info(event, state) when is_struct(event) do
    case resolve_event(event) do
      {event_type, workspace_id, event_data} when is_binary(workspace_id) ->
        Task.Supervisor.start_child(
          Summoner.TaskSupervisor,
          fn -> forward_to_plugins(workspace_id, event_type, event_data) end
        )

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp forward_to_plugins(workspace_id, event_type, event_data) do
    plugins = Plugins.list_enabled_by_capability(workspace_id, "events")

    plugins
    |> Enum.filter(&event_subscribed?(&1, event_type))
    |> Enum.each(&forward_single_event(&1, event_type, event_data))
  end

  defp forward_single_event(plugin, event_type, event_data) do
    conversation_id = Map.get(event_data, "conversation_id")
    external_ref = resolve_external_ref(plugin, conversation_id)

    with {:ok, container} <- get_container_for_plugin(plugin),
         context <- PluginsService.build_context(plugin, container) do
      case PluginClient.send_event(container, context, event_type, event_data, external_ref) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Plugin #{plugin.name} event forward failed: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        Logger.warning("Plugin #{plugin.name} container not available: #{inspect(reason)}")
    end
  end

  defp get_container_for_plugin(plugin) do
    isolation =
      TrustVerifier.effective_isolation(
        plugin.trusted,
        get_in(plugin.manifest, ["isolation"])
      )

    tenant_id = if isolation == :tenant, do: plugin.workspace_id, else: nil
    PluginContainerManager.get_container(plugin.digest, tenant_id)
  end

  defp event_subscribed?(plugin, event_type) do
    subscribed = get_in(plugin.manifest, ["events", "subscribes"]) || []
    event_type in subscribed
  end

  defp resolve_external_ref(_plugin, nil), do: nil

  defp resolve_external_ref(plugin, conversation_id) do
    case Plugins.get_conversation_by_id(plugin.id, conversation_id) do
      %{external_ref: ref} -> ref
      nil -> nil
    end
  end

  defp resolve_event(event) do
    case EventSerializer.serialize(event) do
      {event_type, event_data} ->
        workspace_id = Map.get(event_data, "workspace_id")
        {event_type, workspace_id, event_data}

      nil ->
        nil
    end
  end
end
