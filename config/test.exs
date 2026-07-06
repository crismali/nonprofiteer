import Config
config :nonprofiteer, Oban, testing: :manual
config :ash, disable_async?: true

# No sync-feed watermark lag in tests, so freshly-created rows are immediately visible to the
# changed-since feed. Watermark-exclusion behaviour is tested by overriding this per-test.
config :nonprofiteer, sync_watermark_lag_seconds: 0

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :nonprofiteer, Nonprofiteer.Repo,
  username: System.get_env("DB_USERNAME") || System.get_env("USER"),
  password: System.get_env("DB_PASSWORD"),
  hostname: System.get_env("DB_HOST") || "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  database: "nonprofiteer_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nonprofiteer, NonprofiteerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+rF6/RMTdevXVMUlIVOgKN/JU5sqiUfYUc5kA/cl/ubcfdKopTCfoe+7Bbp8zBme",
  server: false

# In test we don't send emails
config :nonprofiteer, Nonprofiteer.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
