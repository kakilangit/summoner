defmodule Summoner.Services.Plugins.ActionExecutor do
  @moduledoc """
  Processes action requests from plugin containers.

  Actions are workspace-scoped. Supported types:
  - invoke_agent — invoke agent by callname (sync)
  - invoke_agent_async — invoke without waiting
  - emit_event — emit custom event (namespaced: plugin.<name>.<event>)
  - log — write to plugin log
  """

  alias Summoner.Domain.Schemas.Scope
  alias Summoner.Ports.Events
  alias Summoner.Ports.Persistence.Agents
  alias Summoner.Ports.Persistence.Conversations
  alias Summoner.Ports.Persistence.Plugins
  alias Summoner.Services.Agents.Server, as: AgentServer

  require Logger

  @doc "Execute a list of actions from a plugin response."
  def execute_actions(plugin, workspace_id, actions) when is_list(actions) do
    Enum.map(actions, fn action ->
      execute_action(plugin, workspace_id, action)
    end)
  end

  def execute_action(plugin, workspace_id, %{"type" => "invoke_agent"} = action) do
    callname = action["agent"]
    message = action["message"] || ""
    external_ref = action["external_ref"]
    scope = plugin_scope()

    case Agents.get_agent_by_callname(scope, workspace_id, callname) do
      nil ->
        Logger.warning("Plugin #{plugin.name} tried to invoke unknown agent: #{callname}")
        {:error, :agent_not_found}

      agent ->
        conversation = find_or_create_conversation(plugin, workspace_id, agent, external_ref)

        AgentServer.invoke(workspace_id, agent.id, %{
          conversation_id: conversation.id,
          message: message,
          scope: scope
        })
    end
  end

  def execute_action(plugin, workspace_id, %{"type" => "invoke_agent_async"} = action) do
    Task.Supervisor.start_child(
      Summoner.TaskSupervisor,
      fn -> execute_action(plugin, workspace_id, Map.put(action, "type", "invoke_agent")) end
    )

    {:ok, :async}
  end

  def execute_action(plugin, _workspace_id, %{"type" => "emit_event"} = action) do
    event_name = "plugin.#{plugin.name}.#{action["event"]}"
    event_data = action["data"] || %{}

    Events.publish(%Summoner.Domain.Events.PluginEvent{
      plugin_id: plugin.id,
      plugin_name: plugin.name,
      event_name: event_name,
      data: event_data,
      workspace_id: plugin.workspace_id
    })

    {:ok, :emitted}
  end

  def execute_action(plugin, _workspace_id, %{"type" => "log"} = action) do
    level = action["level"] || "info"
    message = action["message"] || ""
    Logger.info("[Plugin #{plugin.name}] [#{level}] #{message}")
    {:ok, :logged}
  end

  def execute_action(plugin, _workspace_id, %{"type" => type}) do
    Logger.warning("Plugin #{plugin.name} sent unsupported action type: #{type}")
    {:error, :unsupported_action}
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp find_or_create_conversation(plugin, workspace_id, agent, external_ref) do
    scope = plugin_scope()

    if external_ref do
      case Plugins.get_conversation_by_ref(plugin.id, external_ref) do
        %{conversation_id: conv_id} ->
          Conversations.get_conversation!(scope, workspace_id, conv_id)

        nil ->
          {:ok, conv} =
            Conversations.create_conversation(scope, %{
              workspace_id: workspace_id,
              agent_id: agent.id,
              title: "Plugin: #{plugin.name}"
            })

          Plugins.upsert_conversation(%{
            plugin_id: plugin.id,
            external_ref: external_ref,
            conversation_id: conv.id
          })

          conv
      end
    else
      {:ok, conv} =
        Conversations.create_conversation(scope, %{
          workspace_id: workspace_id,
          agent_id: agent.id,
          title: "Plugin: #{plugin.name}"
        })

      conv
    end
  end

  # Plugin actions run without a user context.
  # Use a nil-user scope (system scope).
  defp plugin_scope do
    %Scope{user: nil}
  end
end
