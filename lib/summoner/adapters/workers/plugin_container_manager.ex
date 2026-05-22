defmodule Summoner.Adapters.Workers.PluginContainerManager do
  @moduledoc """
  GenServer managing the lifecycle of a single plugin container.

  Started under `Summoner.PluginSupervisor` (DynamicSupervisor) when a
  plugin is enabled. Handles:

  - Container creation and startup via ContainerRuntime port
  - MCP client connection via Anubis.Client (stdio transport)
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
    name = client_name(plugin_id)

    case Registry.lookup(Summoner.PluginRegistry, {:client, plugin_id}) do
      [{_pid, _}] -> {:ok, name}
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
      {:ok, container_id, client_ref} ->
        state = %{state | container_id: container_id, client_pid: client_ref, status: :running}
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
  # Container lifecycle (single path)
  # -------------------------------------------------------------------

  defp start_container(plugin) do
    container_name = container_name(plugin)

    # Clean up any stale resources from previous runs
    cleanup_mcp_client(plugin.id)
    ContainerRuntime.remove(container_name)

    opts = container_opts(plugin, container_name)

    with :ok <- ContainerRuntime.pull(opts.image) do
      start_mcp_client(plugin.id, opts)
    end
  end

  defp cleanup(state) do
    cleanup_mcp_client(state.plugin.id)
    ContainerRuntime.remove(container_name(state.plugin))
  end

  # -------------------------------------------------------------------
  # MCP client lifecycle
  # -------------------------------------------------------------------

  defp start_mcp_client(plugin_id, opts) do
    {command, args} = ContainerRuntime.stdio_transport_args(opts)

    anubis_opts = [
      name: client_name(plugin_id),
      transport_name: transport_name(plugin_id),
      client_info: %{"name" => "Summoner", "version" => "0.1.0"},
      capabilities: %{},
      transport: {:stdio, command: command, args: args, env: %{}}
    ]

    case DynamicSupervisor.start_child(
           Summoner.McpSupervisor,
           {Anubis.Client.Supervisor, anubis_opts}
         ) do
      {:ok, _sup_pid} ->
        client = client_name(plugin_id)

        case Anubis.Client.await_ready(client, timeout: 30_000) do
          :ok -> {:ok, opts.name, client}
          {:error, reason} -> {:error, {:mcp_handshake_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_mcp_client(plugin_id) do
    case Registry.lookup(Summoner.PluginRegistry, {:client, plugin_id}) do
      [{pid, _}] ->
        for {_id, child, _type, _mods} <- DynamicSupervisor.which_children(Summoner.McpSupervisor),
            is_pid(child),
            descendant?(child, pid) do
          DynamicSupervisor.terminate_child(Summoner.McpSupervisor, child)
        end

        :ok

      [] ->
        :ok
    end
  end

  defp descendant?(sup, target) do
    case Supervisor.which_children(sup) do
      children when is_list(children) ->
        Enum.any?(children, fn
          {_, ^target, _, _} -> true
          {_, child, :supervisor, _} when is_pid(child) -> descendant?(child, target)
          _ -> false
        end)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  # -------------------------------------------------------------------
  # Health & restart
  # -------------------------------------------------------------------

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

  # -------------------------------------------------------------------
  # Config resolution
  # -------------------------------------------------------------------

  defp container_opts(plugin, container_name) do
    manifest = plugin.manifest

    %{
      image: manifest["image"],
      name: container_name,
      env: build_env(plugin),
      network: Map.get(manifest, "network", false),
      cpu: get_in(manifest, ["resources", "cpu"]) || "0.5",
      memory: get_in(manifest, ["resources", "memory"]) || "256Mi"
    }
  end

  defp build_env(plugin) do
    config_schema = get_in(plugin.manifest, ["config_schema", "properties"]) || %{}

    plugin.config
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      resolved_value = resolve_config_value(config_schema, k, v)
      Map.put(acc, "PLUGIN_#{String.upcase(k)}", to_string(resolved_value))
    end)
  end

  defp resolve_config_value(config_schema, key, value) do
    if get_in(config_schema, [key, "src"]) == "secret" do
      case Summoner.Repo.get(Summoner.Domain.Schemas.Secret, value) do
        %{encrypted_value: decrypted} -> decrypted
        nil -> value
      end
    else
      value
    end
  end

  # -------------------------------------------------------------------
  # Naming
  # -------------------------------------------------------------------

  defp container_name(plugin), do: "summoner-plugin-#{plugin.id}"

  defp client_name(plugin_id),
    do: {:via, Registry, {Summoner.PluginRegistry, {:client, plugin_id}}}

  defp transport_name(plugin_id),
    do: {:via, Registry, {Summoner.PluginRegistry, {:transport, plugin_id}}}

  defp via(plugin_id),
    do: {:via, Registry, {Summoner.PluginRegistry, plugin_id}}

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_interval)
  end
end
