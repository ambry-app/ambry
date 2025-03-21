defmodule AmbryApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    # attach Sentry to the logger
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    # ensures all migrations have been run on application start
    migrate!()

    config_env = Application.get_env(:ambry, :config_env)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ambry.Supervisor]
    Supervisor.start_link(children(config_env), opts)
  end

  defp shared_children do
    [
      # Start the Telemetry supervisor
      AmbryWeb.Telemetry,
      # Start the Ecto repository
      Ambry.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Ambry.PubSub},
      # Presence
      AmbryWeb.Presence,
      # HTTP Client for Swoosh API based providers (not used for SMTP providers)
      {Finch, name: Ambry.Finch},
      # Starts Oban jobs
      {Oban, oban_config()},
      # Start the Endpoint (http/https)
      AmbryWeb.Endpoint
    ]
  end

  def children(:test), do: shared_children()

  def children(_env) do
    shared_children() ++
      [
        # Search index refresher/warmer
        Supervisor.child_spec({Task, &Ambry.Search.refresh_entire_index!/0},
          id: :refresh_search_index
        ),
        # Headless browser for web-scraping
        AmbryScraping.Marionette,
        # Schedule Oban jobs for all missing thumbnails
        Supervisor.child_spec({Task, &Ambry.Thumbnails.schedule_missing_thumbnails!/0},
          id: :missing_thumbnails
        )
      ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    AmbryWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    Application.fetch_env!(:ambry, Oban)
  end

  defp migrate! do
    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(Ambry.Repo, &Ecto.Migrator.run(&1, :up, all: true))
  end
end
