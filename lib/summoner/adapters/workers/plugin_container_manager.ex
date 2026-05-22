defmodule Summoner.Adapters.Workers.PluginContainerManager do
  @moduledoc """
  GenServer managing the lifecycle of a single plugin container.

  Started under `Summoner.PluginSupervisor` (DynamicSupervisor) when a
  plugin is enabled. Handles:

  - Container creation and startup via ContainerRuntime port
  - MCP client connection via Anubis.Client (stdio transport piped through docker exec)
  - Periodic health check (30s interval)
  - Auto-restart on crash (max 3 restarts, then transition to :error status)
  - Clean shutdown on disable/uninstall
  """

  use GenServer

  alias Summoner.Ports.ContainerRuntime
  alias Summoner.Ports.Persistence.Plugins

  require Logger

  @health_interval :timer.seconds(30)
  @max_restarts 3

  defstruct [
    :plugin,
    :container_id,
    :client_pid,
    restart_count: 0,
    status: :starting
  ]

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(plugin) do
    GenServer.start_link(__MODULE__, plugin, name: via(plugin.id))
  end

  def stop_plugin(plugin_id) do
    case Registry.lookup(Summoner.PluginRegistry, plugin_id) do
      [{pid, _}] -> GenServer.call(pid, :stop_plugin, 30_000)
      [] -> :ok
    end
  end

  def get_client(plugin_id) do
    case Registry.lookup(Summoner.PluginRegistry, plugin_id) do
      [{pid, _}] -> GenServer.call(pid, :get_client)
      [] -> {:error, :not_running}
    end
  end

  def get_status(plugin_id) do
    case Registry.lookup(Summoner.PluginRegistry, plugin_id) do
      [{pid, _}] -> GenServer.call(pid, :get_status)
      [] -> {:error, :not_running}
    end
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(plugin) do
    state = %__MODULE__{plugin: plugin}
    {:ok, state, {:continue, :start_container}}
  end

  @impl true
  def handle_continue(:start_container, state) do
    case start_container(state.plugin) do
      {:ok, container_id} ->
        state = %{state | container_id: container_id, status: :running}
        schedule_health_check()

        Logger.info("Plugin #{state.plugin.name} container started: #{container_id}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Plugin #{state.plugin.name} container failed to start: #{inspect(reason)}")

        transition_to_error(state, "Container start failed: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_call(:stop_plugin, _from, state) do
    cleanup(state)
    {:stop, :normal, :ok, state}
  end

  def handle_call(:get_client, _from, state) do
    {:reply, {:ok, state.client_pid}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    case check_health(state) do
      :ok ->
        schedule_health_check()
        {:noreply, state}

      :unhealthy ->
        handle_unhealthy(state)
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{client_pid: pid} = state) do
    Logger.warning("Plugin #{state.plugin.name} MCP client died: #{inspect(reason)}")
    handle_unhealthy(state)
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup(state)
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp start_container(plugin) do
    manifest = plugin.manifest
    container_name = container_name(plugin)

    # Remove stale container if it exists
    ContainerRuntime.remove(container_name)

    opts = %{
      image: manifest["image"],
      name: container_name,
      env: build_env(plugin),
      network: Map.get(manifest, "network", false),
      cpu: get_in(manifest, ["resources", "cpu"]) || "0.5",
      memory: get_in(manifest, ["resources", "memory"]) || "256Mi"
    }

    with :ok <- ContainerRuntime.pull(opts.image),
         {:ok, container_id} <- ContainerRuntime.create(opts),
         :ok <- ContainerRuntime.start(container_id) do
      {:ok, container_id}
    end
  end

  defp build_env(plugin) do
    plugin.config
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, "PLUGIN_#{String.upcase(k)}", to_string(v))
    end)
  end

  defp container_name(plugin) do
    "summoner-plugin-#{plugin.id}"
  end

  defp check_health(state) do
    if state.container_id && ContainerRuntime.running?(state.container_id) do
      :ok
    else
      :unhealthy
    end
  end

  defp handle_unhealthy(state) do
    if state.restart_count < @max_restarts do
      Logger.warning(
        "Plugin #{state.plugin.name} unhealthy, restarting " <>
          "(#{state.restart_count + 1}/#{@max_restarts})"
      )

      cleanup(state)

      state = %{
        state
        | restart_count: state.restart_count + 1,
          container_id: nil,
          client_pid: nil
      }

      {:noreply, state, {:continue, :start_container}}
    else
      Logger.error("Plugin #{state.plugin.name} exceeded max restarts, transitioning to error")
      transition_to_error(state, "Exceeded maximum restart attempts (#{@max_restarts})")
    end
  end

  defp transition_to_error(state, message) do
    Plugins.update_status(state.plugin, :error, message)
    cleanup(state)
    {:stop, :normal, state}
  end

  defp cleanup(state) do
    if state.container_id do
      ContainerRuntime.stop(state.container_id)
      ContainerRuntime.remove(state.container_id)
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_interval)
  end

  defp via(plugin_id) do
    {:via, Registry, {Summoner.PluginRegistry, plugin_id}}
  end
end
