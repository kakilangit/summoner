defmodule Summoner.Adapters.Workers.PluginContainerManager do
  @moduledoc """
  GenServer managing plugin containers by digest.

  Containers are shared across plugin installations with the same image
  digest (unless tenant-isolated). Orphan containers whose digest has no
  enabled installations are swept on each health-check tick — no mutable
  ref-counting or grace periods needed.

  Started as a singleton under the application supervision tree.
  """

  use GenServer

  alias Summoner.Domain.Schemas.PluginContainer
  alias Summoner.Ports.ContainerRuntime
  alias Summoner.Ports.Persistence.Plugins, as: Persistence
  alias Summoner.Repo

  require Logger

  import Ecto.Query

  @health_interval :timer.seconds(30)
  @max_restarts 3
  @plugin_network "summoner-plugins"

  defstruct restart_counts: %{}

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensure a container is running for the given image/digest.

  Returns existing container or starts a new one.
  """
  def ensure_container(image, digest, isolation, tenant_id) do
    GenServer.call(__MODULE__, {:ensure_container, image, digest, isolation, tenant_id}, 60_000)
  end

  @doc "Get the container record for a plugin installation."
  def get_container(digest, tenant_id) do
    case lookup(digest, tenant_id) do
      %{status: :running} = container -> {:ok, container}
      %{} -> {:error, :not_running}
      nil -> {:error, :not_found}
    end
  end

  @doc "Stop and remove a specific container by its record."
  def stop_container(container_id) do
    GenServer.call(__MODULE__, {:stop_container, container_id}, 30_000)
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(_opts) do
    ensure_plugin_network()
    schedule_health_check()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:ensure_container, image, digest, isolation, tenant_id}, _from, state) do
    tid = if isolation == :tenant, do: tenant_id, else: nil

    case lookup(digest, tid) do
      %{status: :running} = container ->
        {:reply, {:ok, container}, state}

      %{status: :error} = container ->
        cleanup_container(container)
        {reply, state} = start_new_container(image, digest, tid, state)
        {:reply, reply, state}

      nil ->
        {reply, state} = start_new_container(image, digest, tid, state)
        {:reply, reply, state}
    end
  end

  def handle_call({:stop_container, container_id}, _from, state) do
    case Repo.get(PluginContainer, container_id) do
      nil ->
        {:reply, :ok, state}

      container ->
        cleanup_container(container)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    sweep_orphan_containers()
    check_all_containers(state)
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -------------------------------------------------------------------
  # Container lifecycle
  # -------------------------------------------------------------------

  defp start_new_container(image, digest, tenant_id, state) do
    container_name = PluginContainer.container_name_from_image(image)
    callback_token = generate_callback_token(container_name)
    host_mode? = Application.get_env(:summoner, :plugin_host_mode) == :host
    container_port = 9999

    ContainerRuntime.remove(container_name)
    delete_stale_containers(container_name)

    opts = %{
      image: image,
      name: container_name,
      network_name: if(host_mode?, do: "bridge", else: @plugin_network),
      env: %{"PLUGIN_PORT" => to_string(container_port)},
      port: container_port,
      publish_port: host_mode?,
      cpu: "0.5",
      memory: "256m"
    }

    case ContainerRuntime.run_detached(opts) do
      {:ok, docker_container_id} ->
        {host, port} =
          resolve_container_address(
            host_mode?,
            docker_container_id,
            container_name,
            container_port
          )

        attrs = %{
          image: image,
          digest: digest,
          container_id: docker_container_id,
          container_name: container_name,
          host: host,
          port: port,
          status: :running,
          callback_token: callback_token,
          tenant_id: tenant_id
        }

        case %PluginContainer{} |> PluginContainer.changeset(attrs) |> Repo.insert() do
          {:ok, container} ->
            Logger.info(
              "Started plugin container #{container_name} (digest: #{String.slice(digest, 0, 16)})"
            )

            {{:ok, container}, state}

          {:error, changeset} ->
            ContainerRuntime.remove(container_name)
            {{:error, {:db_error, changeset}}, state}
        end

      {:error, reason} ->
        handle_start_failure(state, {digest, tenant_id}, container_name, reason)
    end
  end

  defp handle_start_failure(state, key, container_name, reason) do
    count = Map.get(state.restart_counts, key, 0)

    if count < @max_restarts do
      Logger.warning(
        "Container #{container_name} failed to start (#{count + 1}/#{@max_restarts}): #{inspect(reason)}"
      )

      state = %{state | restart_counts: Map.put(state.restart_counts, key, count + 1)}
      {{:error, reason}, state}
    else
      Logger.error("Container #{container_name} exceeded max restarts")
      {{:error, :max_restarts_exceeded}, state}
    end
  end

  defp cleanup_container(container) do
    ContainerRuntime.remove(container.container_name)
    Repo.delete(container)
  rescue
    Ecto.StaleEntryError -> :ok
  end

  defp delete_stale_containers(container_name) do
    PluginContainer
    |> where([c], c.container_name == ^container_name)
    |> Repo.delete_all()
  end

  # -------------------------------------------------------------------
  # Orphan sweep
  # -------------------------------------------------------------------

  defp sweep_orphan_containers do
    enabled = Persistence.enabled_digests()

    PluginContainer
    |> where([c], c.digest not in ^enabled)
    |> Repo.all()
    |> Enum.each(fn container ->
      Logger.info("Sweeping orphan container #{container.container_name}")
      cleanup_container(container)
    end)
  end

  # -------------------------------------------------------------------
  # Health check
  # -------------------------------------------------------------------

  defp check_all_containers(state) do
    PluginContainer
    |> where([c], c.status == :running)
    |> Repo.all()
    |> Enum.each(&check_single_container(&1, state))
  end

  defp check_single_container(container, state) do
    if ContainerRuntime.running?(container.container_name) do
      :ok
    else
      Logger.warning("Container #{container.container_name} is no longer running")
      handle_container_down(container, state)
    end
  end

  defp handle_container_down(container, state) do
    key = {container.digest, container.tenant_id}
    count = Map.get(state.restart_counts, key, 0)
    enabled = Persistence.enabled_digests()

    if count < @max_restarts and container.digest in enabled do
      Logger.info("Restarting container #{container.container_name}")
      cleanup_container(container)
      start_new_container(container.image, container.digest, container.tenant_id, state)
    else
      container
      |> PluginContainer.status_changeset(:error)
      |> Repo.update()
    end
  end

  # -------------------------------------------------------------------
  # Lookup
  # -------------------------------------------------------------------

  defp lookup(digest, nil) do
    PluginContainer
    |> where([c], c.digest == ^digest and is_nil(c.tenant_id))
    |> Repo.one()
  end

  defp lookup(digest, tenant_id) do
    Repo.get_by(PluginContainer, digest: digest, tenant_id: tenant_id)
  end

  defp resolve_container_address(true, container_id, fallback_name, container_port) do
    case ContainerRuntime.host_port(container_id, container_port) do
      {:ok, mapped_port} -> {"localhost", mapped_port}
      {:error, _} -> {fallback_name, container_port}
    end
  end

  defp resolve_container_address(false, _container_id, container_name, container_port) do
    {container_name, container_port}
  end

  # -------------------------------------------------------------------
  # Auth
  # -------------------------------------------------------------------

  defp generate_callback_token(container_name) do
    secret = Application.get_env(:summoner, :plugin_callback_secret, "summoner-plugin-secret")

    :crypto.mac(:hmac, :sha256, secret, container_name)
    |> Base.encode16(case: :lower)
  end

  # -------------------------------------------------------------------
  # Scheduling
  # -------------------------------------------------------------------

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_interval)
  end

  defp ensure_plugin_network do
    if Application.get_env(:summoner, :plugin_host_mode) == :host do
      Logger.debug("host mode: skipping plugin network creation")
    else
      case ContainerRuntime.ensure_network(@plugin_network) do
        :ok ->
          Logger.info("plugin network '#{@plugin_network}' ready")

        {:error, reason} ->
          Logger.error("failed to create plugin network: #{inspect(reason)}")
      end
    end
  end
end
