import Config

# In test we don't send emails
config :ambry, Ambry.Mailer, adapter: Swoosh.Adapters.Test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ambry, Ambry.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ambry_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ambry, AmbryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+51PLj+Ps1WTQA07qymnblv+HTHse1oXrBZ8Y+O2XlpelIA5QnHb4rWGZ7/xGj3e",
  server: false

# allows Oban to bypass all database interaction and run jobs immediately in the
# process that enqueued them.
config :ambry, Oban, testing: :manual

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Print only warnings and errors during test
config :logger, level: :warning

# Disable os_mon for tests
config :os_mon,
  start_cpu_sup: false,
  start_memsup: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
