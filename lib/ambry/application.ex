defmodule Ambry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    # ensures all migrations have been run on application start
    migrate!()

    children = [
      # Start the Ecto repository
      Ambry.Repo,
      # Start the Telemetry supervisor
      AmbryWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Ambry.PubSub},
      # Start the Endpoint (http/https)
      AmbryWeb.Endpoint,
      # Start a worker by calling: Ambry.Worker.start_link(arg)
      # Starts Oban jobs
      {Oban, oban_config()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ambry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    # coveralls-ignore-start
    AmbryWeb.Endpoint.config_change(changed, removed)
    # coveralls-ignore-stop
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
