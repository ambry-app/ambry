# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ambry,
  ecto_repos: [Ambry.Repo],
  user_registration_enabled: true

# Configures the endpoint
config :ambry, AmbryWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: AmbryWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Ambry.PubSub,
  live_view: [signing_salt: "GndRpmmp"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ambry, Ambry.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Add audiobook mime types
config :mime, :types, %{
  "audio/mp4a-latm" => ["m4a", "m4b"]
}

# Configure Oban
config :ambry, Oban,
  repo: Ambry.Repo,
  plugins: [Oban.Plugins.Pruner],
  # Keep number of media workers low to not starve the host of resources
  queues: [media: 4]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
