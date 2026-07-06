# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

config :ash_json_api,
  # Render public calculations when a query loads them — the sync feed's `:changed_since` action
  # loads `event_type` so it appears in each record's attributes (D16).
  show_public_calculations_when_loaded?: true,
  authorize_update_destroy_with_error?: true

config :nonprofiteer, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  # `:ingest_bulk` is deliberately low-concurrency: a monthly BMF fan-out (a handful of large
  # regional extracts) shouldn't saturate the box or starve other work. Bump when the
  # incremental 990 parse queue lands alongside it.
  # `:ingest_incremental` runs the index-driven 990 parse jobs — kept separate from the bulk
  # BMF lane so a monthly backfill flood can't starve the current month's parse work.
  queues: [default: 10, ingest_bulk: 4, ingest_incremental: 8],
  # Monthly BMF ingest — the coordinator fans out to per-extract jobs. IRS drops the EO BMF
  # early each month; run on the 5th to let the drop settle. The group-exemption reconcile runs
  # a day later (6th), once the fan-out has landed, since it's global across all state files.
  # (Both disabled in test via `testing: :manual`.)
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 6 5 * *", Nonprofiteer.Ingest.BmfCoordinatorWorker},
       {"0 6 6 * *", Nonprofiteer.Ingest.BmfReconcileWorker},
       # 990 e-file parse runs after the BMF spine + reconcile have settled, so org lookups by
       # EIN hit a current spine (a missing org is an orphan skip, not a hard failure).
       {"0 6 7 * *", Nonprofiteer.Ingest.EfileIndexWorker},
       # Amendment supersede runs after the parse settles — links superseded filings so the
       # sync feed emits the status change (D10/D16).
       {"0 6 8 * *", Nonprofiteer.Ingest.EfileSupersedeWorker}
     ]}
  ],
  repo: Nonprofiteer.Repo

config :spark,
  formatter: [
    "Ash.Resource": [section_order: [:json_api, :admin, :postgres]],
    "Ash.Domain": [section_order: [:json_api, :admin]]
  ]

config :ash, known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :nonprofiteer,
  ecto_repos: [Nonprofiteer.Repo],
  ash_domains: [Nonprofiteer.Orgs, Nonprofiteer.Ingest],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :nonprofiteer, NonprofiteerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NonprofiteerWeb.ErrorHTML, json: NonprofiteerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Nonprofiteer.PubSub,
  live_view: [signing_salt: "Zpc6/vmS"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :nonprofiteer, Nonprofiteer.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  nonprofiteer: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  nonprofiteer: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
