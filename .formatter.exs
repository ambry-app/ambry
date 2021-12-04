[
  line_length: 120,
  import_deps: [:ecto, :phoenix, :surface],
  plugins: [Surface.Formatter.Plugin],
  inputs: [
    "*.{ex,exs}",
    "priv/*/seeds.exs",
    "{config,lib,test}/**/*.{ex,exs,sface}"
  ],
  subdirectories: ["priv/*/migrations"]
]
