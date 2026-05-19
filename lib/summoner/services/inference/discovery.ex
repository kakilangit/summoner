defmodule Summoner.Services.Inference.Discovery do
  @moduledoc """
  GenServer that periodically probes all providers and updates their status.

  On startup, probes all providers immediately. Then re-probes on a
  configurable interval (default 60 seconds).
  """

  use GenServer

  require Logger

  alias Arcanum.Probe
  alias Summoner.Adapters.Persistence.Providers

  @default_interval :timer.seconds(60)

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Triggers an immediate probe of all providers.
  """
  def probe_all(server \\ __MODULE__) do
    GenServer.cast(server, :probe_all)
  end

  # -------------------------------------------------------------------
  # Server callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    schedule_probe(0)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_cast(:probe_all, state) do
    do_probe_all()
    {:noreply, state}
  end

  @impl true
  def handle_info(:probe, state) do
    do_probe_all()
    schedule_probe(state.interval)
    {:noreply, state}
  end

  # -------------------------------------------------------------------
  # Internal
  # -------------------------------------------------------------------

  defp do_probe_all do
    providers = Providers.list_all_providers()

    providers
    |> Task.async_stream(&probe_and_update/1,
      max_concurrency: 10,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Stream.run()
  end

  defp probe_and_update(provider) do
    status = Probe.probe_provider(provider)

    if provider.status != status do
      Providers.update_status(provider, status)
      Logger.info("Provider #{provider.name} (#{provider.id}) status changed to #{status}")
    end
  end

  defp schedule_probe(delay) do
    Process.send_after(self(), :probe, delay)
  end
end
