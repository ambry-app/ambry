defmodule Ambry.Metadata do
  @moduledoc false

  # Exports are the boundary's public API: the Providers facade and
  # Registry (never the provider modules or their HTTP clients — all calls
  # route through the facade for caching and capability checks), the
  # Provider behaviour with its normalized structs, and the legacy cached
  # facades until 1e retires them. AmbryScraping would be inherited from
  # the parent boundary anyway; it's listed to make the dependency visible.
  use Boundary,
    deps: [Ambry.Repo, AmbryScraping],
    exports: [
      Audible,
      GoodReads,
      {Provider, []},
      Providers,
      Registry
    ]
end
