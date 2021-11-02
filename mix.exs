defmodule Ambry.MixProject do
  use Mix.Project

  def project do
    [
      app: :ambry,
      version: "0.2.0",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ambry.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 2.0"},
      {:credo, "~> 1.6.0-rc.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.6"},
      {:file_size, "~> 3.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:natural_sort, "~> 0.3"},
      {:oban, "~> 2.9"},
      {:phoenix, "~> 1.6"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_dashboard, ">= 0.5.3 and < 0.6.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, ">= 0.16.0 and < 0.17.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:surface, "~> 0.6"},
      {:surface_formatter, "~> 0.6"},
      {:swoosh, "~> 1.3"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["cmd --cd assets npm run deploy", "phx.digest"],
      format: ["format", "surface.format"]
    ]
  end
end
