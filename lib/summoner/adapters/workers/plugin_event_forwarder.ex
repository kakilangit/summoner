defmodule Summoner.Adapters.Workers.PluginEventForwarder do
  @moduledoc """
  GenServer that subscribes to global PubSub and forwards domain events
  to enabled plugin containers with `events` capability.

  Enriches events with `external_ref` when the conversation has a
  plugin conversation mapping.
  """

  use GenServer

  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Plugins.ActionExecutor
  alias Summoner.Services.Plugins.ProtocolHandler

  require Logger

  # Domain event structs → event_type string mapping (same as EventRuleEvaluator)
  @event_type_map %{
    Summoner.Domain.Events.InvocationStarted => "invocation.started",
    Summoner.Domain.Events.InvocationCompleted => "invocation.completed",
    Summoner.Domain.Events.InvocationFailed => "invocation.failed",
    Summoner.Domain.Events.PipelineRunStatus => "pipeline.started",
    Summoner.Domain.Events.PipelineStageStatus => "pipeline.completed",
    Summoner.Domain.Events.SwarmTurn => "swarm.turn",
    Summoner.Domain.Events.SwarmDone => "swarm.done",
    Summoner.Domain.Events.SwarmTimeout => "swarm.timeout",
    Summoner.Domain.Events.WebhookTriggered => "webhook.triggered",
    Summoner.Domain.Events.WebhookFailed => "webhook.failed",
    Summoner.Domain.Events.Failover => "failover",
    Summoner.Domain.Events.MediaGenerationStarted => "media.started",
    Summoner.Domain.Events.MediaGenerationCompleted => "media.completed",
    Summoner.Domain.Events.MediaGenerationFailed => "media.failed",
    Summoner.Domain.Events.AgentConfigChanged => "agent.config_changed"
  }

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
    |> Enum.each(fn plugin ->
      conversation_id = Map.get(event_data, "conversation_id")
      external_ref = resolve_external_ref(plugin, conversation_id)

      case ProtocolHandler.send_event(plugin, event_type, event_data, external_ref) do
        {:ok, %{"actions" => actions}} when is_list(actions) ->
          ActionExecutor.execute_actions(plugin, workspace_id, actions)

        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Plugin #{plugin.name} event forward failed: #{inspect(reason)}")
      end
    end)
  end

  defp event_subscribed?(plugin, event_type) do
    subscribed = get_in(plugin.manifest, ["events", "subscribes"]) || []
    event_type in subscribed
  end

  defp resolve_external_ref(_plugin, nil), do: nil

  defp resolve_external_ref(plugin, conversation_id) do
    case Plugins.get_conversation_by_ref(plugin.id, conversation_id) do
      %{external_ref: ref} -> ref
      nil -> nil
    end
  end

  defp resolve_event(event) do
    event_type = Map.get(@event_type_map, event.__struct__)

    if event_type do
      workspace_id = Map.get(event, :workspace_id)
      event_data = event_to_map(event, event_type)
      {event_type, workspace_id, event_data}
    else
      nil
    end
  end

  defp event_to_map(event, event_type) do
    event
    |> Map.from_struct()
    |> Map.put(:event_type, event_type)
    |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_value(v) when is_atom(v), do: to_string(v)
  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v
end
