import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/summoner start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if log_level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(log_level)
end

# Structured JSON logging — enabled in prod or when LOG_FORMAT=json
if config_env() == :prod or System.get_env("LOG_FORMAT") == "json" do
  config :logger, :default_handler, formatter: LoggerJSON.Formatters.Basic.new(metadata: :all)
end

if System.get_env("PHX_SERVER") do
  config :summoner, SummonerWeb.Endpoint, server: true
end

config :summoner, SummonerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4100"))]

if data_dir = System.get_env("DATA_DIR") do
  config :summoner, :data_dir, data_dir
end

config :summoner, :local_mode, System.get_env("LOCAL_MODE", "false") == "true"

if config_env() == :prod do
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
      """

  config :summoner, Summoner.Adapters.Crypto.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)
      }
    ]

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :summoner, Summoner.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6,
    types: Summoner.PostgrexTypes

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT", "4000"))
  scheme = System.get_env("PHX_SCHEME", "https")

  config :summoner, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :summoner, SummonerWeb.Endpoint,
    url: [host: host, port: port, scheme: scheme],
    http: [
      port: port,
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :summoner, SummonerWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :summoner, SummonerWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

# SMTP mailer configuration — applies to all environments when SMTP_HOST is set.
# In dev without SMTP_HOST, falls back to Swoosh.Adapters.Local (see config.exs).
smtp_host = System.get_env("SMTP_HOST")

if smtp_host do
  host = System.get_env("PHX_HOST") || "localhost"

  :public_key.cacerts_load()
  cacerts = :public_key.cacerts_get()

  ssl_opts = [
    cacerts: cacerts,
    verify: :verify_peer,
    depth: 3,
    server_name_indication: String.to_charlist(smtp_host),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]

  config :summoner, Summoner.Adapters.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    username: System.get_env("SMTP_USER") || "",
    password: System.get_env("SMTP_PASSWORD") || "",
    ssl: System.get_env("SMTP_SSL") == "true",
    tls: :if_available,
    auth: :if_available,
    sockopts: ssl_opts,
    ssl_options: ssl_opts,
    tls_options: ssl_opts

  smtp_from = System.get_env("SMTP_FROM") || "noreply@#{host}"
  config :summoner, :mailer_from, smtp_from

  # Disable Swoosh local mailbox when real SMTP is configured
  config :swoosh, serve_mailbox: false

  config :summoner, :smtp_configured?, true
end

if copilot_client_id = System.get_env("COPILOT_CLIENT_ID") do
  config :arcanum, copilot_client_id: copilot_client_id
end

# OpenTelemetry — enable trace export when OTEL endpoint is set
if otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry, traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_endpoint: otel_endpoint
end
