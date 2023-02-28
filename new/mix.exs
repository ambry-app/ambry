defmodule Ambry.MixProject do
  use Mix.Project

  def project do
    [
      app: :ambry,
      version: "0.3.1",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix]
      ]
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
      {:argon2_elixir, "~> 3.0"},
      {:bandit, "~> 0.6"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dataloader, "~> 1.0"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:earmark, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.5", runtime: Mix.env() == :dev},
      {:ex_fontawesome, "~> 0.7"},
      {:ex_machina, "~> 2.7", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: :test},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:familiar, "~> 0.1"},
      {:file_size, "~> 3.0"},
      {:finch, "~> 0.13"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.20"},
      {:hashids, "~> 2.0"},
      # TODO: remove me
      {:heroicons, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:natural_sort, "~> 0.3"},
      {:oban, "~> 2.11"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_dashboard, "~> 0.7.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # TODO: switch back to published version once this fix is released:
      # https://github.com/phoenixframework/phoenix_live_view/pull/2387
      {:phoenix_live_view, "~> 0.18.16"},
      {:phoenix, "~> 1.7.0"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:sweet_xml, "~> 0.7"},
      {:swoosh, "~> 1.3"},
      {:tailwind_formatter, "~> 0.3.1", only: [:dev, :test], runtime: false},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "seed"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "ecto.seed": ["run priv/repo/seeds.exs"],
      "seed.download": ["cmd ./script/download_seed_files.sh"],
      seed: ["ecto.seed", "seed.download"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
