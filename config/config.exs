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

# Postgres JIT prices a query by its *estimated* cost, and the flat views'
# correlated subqueries estimate high enough to trip it — universes_flat spent
# ~285ms compiling 43 JIT functions to return zero rows. Short OLTP queries
# never win that trade.
config :ambry, Ambry.Repo, parameters: [jit: "off"]

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
  # Prune jobs older than 1 day
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    # A job whose node died stays `executing` forever without this: the
    # pruner only ever touches finished jobs, so an orphan is invisible to
    # it. Two of them had been sitting in the dev database for two days,
    # and the cost is not cosmetic — `Ambry.Inbox.Progress` reads a job's
    # state, so their items wore the busy scrim and refused clicks
    # permanently, and the overview counted them as work in flight.
    #
    # **The window has to outlast the longest legitimate job**, because
    # Lifeline is naive: it rescues by age alone and cannot tell a dead
    # node from a slow one. The longest thing Ambry runs is an import
    # copying a release off a NAS, minutes rather than hours — but running
    # one twice would place the same files twice, so the margin is wider
    # than the hour Lifeline defaults to.
    {Oban.Plugins.Lifeline, rescue_after: to_timeout(hour: 2)},
    # Discovery hourly: a watched folder gains releases on its own schedule
    # and the operator shouldn't have to press a button to find out.
    #
    # Reconciliation nightly at 04:00, an hour and a half after the backup,
    # because it stats every playable file in the library and there's no
    # reason for that to compete with anything. Files don't vanish often;
    # noticing within a day is soon enough.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Ambry.Inbox.RunDiscovery},
       {"0 4 * * *", Ambry.Media.RunReconciliation},
       # Organizing is triggered by the edits that invalidate a path, so this
       # is the backstop for the one thing no edit can announce: a change to
       # the naming template itself, which invalidates every path at once.
       {"30 4 * * *", Ambry.Media.RunOrganize}
     ]}
  ],
  # `metadata` is deliberately serial: auto-matching a freshly scanned library
  # is hundreds of lookups against shared public instances that rate-limit.
  # The `media` queue went with the transcode pipeline — it existed to keep a
  # handful of ffmpeg runs from starving the host, and nothing enqueues to it.
  queues: [default: 10, pub_sub: 10, images: 4, metadata: 1]

config :ambry,
  ecto_repos: [Ambry.Repo],
  generators: [timestamp_type: :utc_datetime],
  user_registration_enabled: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.9",
  ambry: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

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

# Configure Sentry
config :sentry,
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  client: Ambry.SentryFinchHTTPClient,
  integrations: [
    oban: [capture_errors: true]
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.17",
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
