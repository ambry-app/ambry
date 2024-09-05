# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ambry, Ambry.Mailer, adapter: Swoosh.Adapters.Local

# Configures the endpoint
config :ambry, AmbryWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: AmbryWeb.ErrorHTML, json: AmbryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ambry.PubSub,
  live_view: [signing_salt: "GndRpmmp"]

# Configure Oban
config :ambry, Oban,
  repo: Ambry.Repo,
  plugins: [Oban.Plugins.Pruner],
  # Keep number of media workers low to not starve the host of resources
  queues: [media: 4]

config :ambry,
  ecto_repos: [Ambry.Repo],
  generators: [timestamp_type: :utc_datetime],
  user_registration_enabled: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.23.1",
  ambry: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :ex_fontawesome, type: "solid"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Add audiobook mime types
config :mime, :types, %{
  "audio/mp4a-latm" => ["m4a", "m4b"]
}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.10",
  ambry: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
