import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :summoner, Summoner.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT", "25432")),
  database: "summoner_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Summoner.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :summoner, SummonerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4102],
  secret_key_base: "/emAAY3eHo1+1oC55aHwRpq11vHIBWcG6CATwT1+aTwR+bdKJljFyaNcQX+Gl1CC",
  server: false

# In test we don't send emails
config :summoner, Summoner.Adapters.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Oban inline testing mode
config :summoner, Oban, testing: :inline

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Cloak encryption key for test
config :summoner, Summoner.Adapters.Crypto.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!("dVVDNGJoUUFBZThLQXFzWXVSc2RKUVVJbmtNQ2xONXc=")
    }
  ]

# Use Mox HTTP client for inference adapters in tests
config :summoner, :http_client, Summoner.Ports.HTTPClientMock
config :arcanum, :http_client, Summoner.Ports.HTTPClientMock

# Disable Discovery GenServer in tests
config :summoner, :start_discovery, false

# Disable ModelProfile.Registry in tests (uses HTTP client at boot time)
config :summoner, :start_model_registry, false

# Disable theme init in tests (requires DB seeding)
config :summoner, :start_theme_init, false

# Disable MCP server in tests (starts transport)
config :summoner, :start_mcp_server, false

# Disable event workers in tests (subscribe to global PubSub, spawn tasks without sandbox ownership)
config :summoner, :start_event_rule_evaluator, false
config :summoner, :start_plugin_event_forwarder, false
config :summoner, :start_plugin_container_manager, false

# Use a temporary directory for workspace data in tests
config :summoner, :data_dir, Path.join(System.tmp_dir!(), "summoner_test")
