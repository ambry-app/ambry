defmodule AmbryScraping do
  @moduledoc """
  API clients for external audiobook-metadata services (Audible catalog,
  Audnexus). Wrapped by the `Ambry.Metadata` provider layer — no browser
  scraping remains.
  """

  use Boundary,
    type: :strict,
    deps: [Jason, Floki, Logger, Req],
    exports: [{Audible, []}, {Audnexus, []}]
end
