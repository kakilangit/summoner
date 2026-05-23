defmodule Summoner.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Summoner.Adapters.Persistence.Themes
  alias Summoner.Services.Inference.Discovery
  alias Summoner.Services.Plugins

  @impl true
  def start(_type, _args) do
    Application.put_env(:summoner, :admin_email, System.get_env("ADMIN_EMAIL"))

    # Attach OpenTelemetry instrumenters before supervision tree starts
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:summoner, :repo])

    children =
      [
        SummonerWeb.Telemetry,
        Summoner.Repo,
        {DNSCluster, query: Application.get_env(:summoner, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Summoner.PubSub},
        {Registry, keys: :unique, name: Summoner.AgentRegistry},
        {Registry, keys: :unique, name: Summoner.McpRegistry},
        {DynamicSupervisor, name: Summoner.AgentSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: Summoner.McpSupervisor, strategy: :one_for_one}
      ] ++
        maybe_plugin_container_manager() ++
        [
          {Registry, keys: :unique, name: Summoner.Adapters.Persistence.A2ARegistry},
          {DynamicSupervisor,
           name: Summoner.Adapters.Persistence.A2ASupervisor, strategy: :one_for_one},
          {Task.Supervisor, name: Summoner.TaskSupervisor},
          Summoner.Services.EventLog,
          Summoner.Services.Agents.ProcessMonitor,
          {Oban, Application.fetch_env!(:summoner, Oban)},
          Summoner.Adapters.Crypto.Vault
        ] ++
        maybe_event_rule_evaluator() ++
        maybe_plugin_event_forwarder() ++
        maybe_registry() ++
        maybe_discovery() ++
        maybe_theme_init() ++
        maybe_mcp_server() ++
        maybe_docs_generation() ++
        [
          # Start to serve requests, typically the last entry
          SummonerWeb.Endpoint,
          # Boot enabled plugins after everything is ready
          Supervisor.child_spec(
            {Task, &Plugins.start_enabled_plugins/0},
            id: :plugin_boot
          )
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Summoner.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SummonerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_registry do
    if Application.get_env(:summoner, :start_model_registry, true) do
      [Arcanum.ModelProfile.Registry]
    else
      []
    end
  end

  defp maybe_discovery do
    if Application.get_env(:summoner, :start_discovery, true) do
      [Discovery]
    else
      []
    end
  end

  defp maybe_theme_init do
    if Application.get_env(:summoner, :start_theme_init, true) do
      [{Task, &Themes.seed_builtins/0}]
    else
      []
    end
  end

  defp maybe_mcp_server do
    if Application.get_env(:summoner, :start_mcp_server, true) do
      [{Summoner.Adapters.MCP.Server, transport: :streamable_http}]
    else
      []
    end
  end

  defp maybe_event_rule_evaluator do
    if Application.get_env(:summoner, :start_event_rule_evaluator, true) do
      [Summoner.Adapters.Workers.EventRuleEvaluator]
    else
      []
    end
  end

  defp maybe_plugin_event_forwarder do
    if Application.get_env(:summoner, :start_plugin_event_forwarder, true) do
      [Summoner.Adapters.Workers.PluginEventForwarder]
    else
      []
    end
  end

  defp maybe_plugin_container_manager do
    if Application.get_env(:summoner, :start_plugin_container_manager, true) do
      [Summoner.Adapters.Workers.PluginContainerManager]
    else
      []
    end
  end

  @serve_docs Application.compile_env(:summoner, :serve_docs, false)

  defp maybe_docs_generation do
    if @serve_docs do
      [
        Supervisor.child_spec(
          {Task, &Summoner.Docs.generate/0},
          id: :docs_generation
        )
      ]
    else
      []
    end
  end
end
