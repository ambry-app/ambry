[
  import_deps: [:ecto, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs,heex}",
    "priv/*/seeds.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}"
  ],
  subdirectories: ["priv/*/migrations"],
  heex_line_length: 120
]
