[
  import_deps: [:absinthe, :ecto, :ecto_sql, :phoenix, :mneme, :oban, :oban_web],
  subdirectories: ["priv/*/migrations"],
  plugins: [
    Quokka,
    TailwindFormatter,
    Phoenix.LiveView.HTMLFormatter,
    Ambry.GraphQLSigilFormatter
  ],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  line_length: 98,
  heex_line_length: 120
]
