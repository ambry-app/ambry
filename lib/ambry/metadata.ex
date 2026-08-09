defmodule Ambry.Metadata do
  @moduledoc false

  # Exports are the boundary's public API: the Providers facade and
  # Registry (never the provider modules or their HTTP clients — all calls
  # route through the facade for caching and capability checks) and the
  # Provider behaviour with its normalized structs. AmbryScraping would be
  # inherited from the parent boundary anyway; it's listed to make the
  # dependency visible.
  use Boundary,
    deps: [Ambry.Repo, Ambry.Utils, AmbryScraping],
    exports: [
      {Provider, []},
      # with its submodules: `Match` is the shape every caller pattern-matches
      # on, the same reason `Provider`'s normalized structs are exported
      {PersonSearch, []},
      Providers,
      Registry,
      # the multi-provider fan-out — the piece the admin forms converge on
      Search
    ]
end
