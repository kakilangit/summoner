# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :summoner, :scopes,
  user: [
    default: true,
    module: Summoner.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Summoner.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :summoner,
  ecto_repos: [Summoner.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  data_dir: Path.expand("~/.summoner"),
  local_timezone: "Europe/Berlin"

# Configure Elixir to use the tz database for timezone conversions
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure the endpoint
config :summoner, SummonerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SummonerWeb.ErrorHTML, json: SummonerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Summoner.PubSub,
  live_view: [signing_salt: "rdXn6aTJ"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :summoner, Summoner.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  summoner: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  summoner: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban job processing
config :summoner, Oban,
  repo: Summoner.Repo,
  queues: [default: 10, reaper: 2, media: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 3_600},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Summoner.Workers.InvocationReaper},
       {"* * * * *", Summoner.Workers.SubtaskReaper},
       {"* * * * *", Summoner.Workers.PipelineScheduler},
       {"0 3 * * *", Summoner.Workers.MediaCleanup}
     ]}
  ]

config :summoner, :smtp_configured?, true

config :arcanum, copilot_client_id: "Ov23li8tweQw6odWQebz"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
