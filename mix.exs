defmodule Ambry.MixProject do
  use Mix.Project

  def project do
    [
      app: :ambry,
      version: "1.4.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      npm_deps: npm_deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ],
      boundary: [
        default: [
          check: [aliases: true]
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AmbryApp.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_relay, "~> 1.5"},
      {:absinthe, "~> 1.7"},
      {:argon2_elixir, "~> 4.0"},
      {:bandit, "~> 1.0"},
      {:boundary, github: "sasa1977/boundary", runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dataloader, "~> 2.0"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:ex_fontawesome, "~> 0.7"},
      {:ex_machina, "~> 2.7", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: :test},
      {:faker, "~> 0.19.0-alpha.1", only: [:dev, :test]},
      {:familiar, "~> 0.1"},
      {:file_size, "~> 3.0"},
      {:file_system, "~> 1.0"},
      {:finch, "~> 0.13"},
      {:floki, ">= 0.30.0"},
      {:gettext, "~> 0.20"},
      {:hashids, "~> 2.0"},
      {:image, "~> 0.37"},
      {:jason, "~> 1.2"},
      {:mneme, ">= 0.0.0", only: [:dev, :test]},
      {:natural_order, "~> 0.3"},
      {:npm_deps, "~> 0.3", runtime: false},
      {:oban_web, "~> 2.11"},
      {:oban, "~> 2.20"},
      {:patch, "~> 0.13", only: [:test]},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 4.0", override: true},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0", override: true},
      {:phoenix, "~> 1.7.0"},
      {:postgrex, ">= 0.0.0"},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:req, "~> 0.3"},
      {:sentry, "~> 11.0"},
      {:swoosh, "~> 1.3"},
      {:tailwind_formatter, "~> 0.4.0", only: [:dev, :test], runtime: false},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:thumbhash, "~> 0.1.0-alpha.0"}
    ]
  end

  def npm_deps do
    [
      {:"decimal.js", "10.6.0"},
      {:"platform-detect", "3.0.1"},
      {:"shaka-player", "4.16.0"},
      {:topbar, "3.0.0"}
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
      setup: ["deps.get", "npm_deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "deps.get_all": ["deps.get", "npm_deps.get"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.seed": ["run priv/repo/seeds.exs"],
      "seed.download": ["cmd ./script/download_seed_files.sh"],
      seed: ["ecto.seed", "seed.download"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind ambry", "esbuild ambry"],
      "assets.deploy": ["tailwind ambry --minify", "esbuild ambry --minify", "phx.digest"],
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "credo",
        "dialyzer"
      ]
    ]
  end
end
