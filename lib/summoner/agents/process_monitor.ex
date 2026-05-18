defmodule Summoner.Agents.ProcessMonitor do
  @moduledoc """
  Centralized monitor for AgentServer processes.

  Watches all AgentServer pids via `Process.monitor/1`. When an
  AgentServer crashes unexpectedly, marks its in-flight invocations
  as failed and emits an event to the EventLog.

  ## How it works

  1. AgentServer calls `ProcessMonitor.monitor/3` after starting
  2. ProcessMonitor stores `{ref => {workspace_id, agent_id}}` mapping
  3. On `{:DOWN, ref, ...}`, it:
     - Marks running invocations for that agent as failed
     - Emits an event to the EventLog
     - Cleans up the monitor mapping
  """

  use GenServer

  require Logger

  alias Summoner.Orchestration

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers an AgentServer pid for crash monitoring.
  """
  def monitor(workspace_id, agent_id, pid, name \\ __MODULE__) do
    GenServer.cast(name, {:monitor, workspace_id, agent_id, pid})
  end

  @doc """
  Removes monitoring for an agent (e.g. on graceful shutdown).
  """
  def demonitor(workspace_id, agent_id, name \\ __MODULE__) do
    GenServer.cast(name, {:demonitor, workspace_id, agent_id})
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{monitors: %{}, agents: %{}}}
  end

  @impl true
  def handle_cast({:monitor, workspace_id, agent_id, pid}, state) do
    key = {workspace_id, agent_id}

    # Demonitor previous if exists
    state = maybe_demonitor(state, key)

    ref = Process.monitor(pid)

    state = %{
      state
      | monitors: Map.put(state.monitors, ref, key),
        agents: Map.put(state.agents, key, ref)
    }

    {:noreply, state}
  end

  def handle_cast({:demonitor, workspace_id, agent_id}, state) do
    {:noreply, maybe_demonitor(state, {workspace_id, agent_id})}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {{workspace_id, agent_id}, monitors} ->
        handle_agent_down(workspace_id, agent_id, reason)
        agents = Map.delete(state.agents, {workspace_id, agent_id})
        {:noreply, %{state | monitors: monitors, agents: agents}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp handle_agent_down(_workspace_id, _agent_id, :normal), do: :ok
  defp handle_agent_down(_workspace_id, _agent_id, :shutdown), do: :ok
  defp handle_agent_down(_workspace_id, _agent_id, {:shutdown, _}), do: :ok

  defp handle_agent_down(workspace_id, agent_id, reason) do
    Logger.error(
      "AgentServer crashed: workspace=#{workspace_id} agent=#{agent_id} reason=#{inspect(reason)}"
    )

    # Mark running invocations as failed
    running_invocations = Orchestration.list_running_invocations(agent_id)

    Enum.each(running_invocations, fn inv ->
      Orchestration.update_invocation_status(inv, :failed, %{
        end_reason: :failed,
        output: %{"error" => "agent_crashed", "reason" => inspect(reason)}
      })
    end)

    # Emit to in-memory EventLog
    Summoner.EventLog.append(:agent_crashed, %{
      workspace_id: workspace_id,
      agent_id: agent_id,
      reason: inspect(reason),
      affected_invocations: length(running_invocations)
    })
  rescue
    e ->
      Logger.warning("ProcessMonitor failed to handle agent down: #{Exception.message(e)}")
  end

  defp maybe_demonitor(state, key) do
    case Map.get(state.agents, key) do
      nil ->
        state

      old_ref ->
        Process.demonitor(old_ref, [:flush])

        %{
          state
          | monitors: Map.delete(state.monitors, old_ref),
            agents: Map.delete(state.agents, key)
        }
    end
  end
end
