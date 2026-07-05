import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sahla, Sahla.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sahla_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Run Oban jobs inline (no poller/queues/plugins) so tests are deterministic.
config :sahla, Oban, testing: :inline

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sahla, SahlaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "M77/yIuN10HUqunYzkVn/8pNJugLr15KbWklGVJa676szL8nCABHFKtBE7xFlUOd",
  server: false

# Weak Argon2 parameters keep password-hashing tests fast (never used in prod).
config :argon2_elixir, t_cost: 1, m_cost: 8

# In test we don't send emails
config :sahla, Sahla.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Analytics are disabled in test so local runs never phone home.
config :sahla, :analytics_enabled, false

# Golden persona drift threshold for rating fixtures (100 centimes = 1 MAD).
config :sahla, :rating_drift_threshold_centimes, 100
