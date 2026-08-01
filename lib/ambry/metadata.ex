defmodule Ambry.Metadata do
  @moduledoc false

  use Boundary,
    deps: [Ambry.Repo],
    exports: [
      Audible,
      GoodReads,
      {Provider, []},
      {Providers, []},
      Registry
    ]
end
