defmodule AmbryScraping do
  @moduledoc """
  Provides web and API scraping for GoodReads, Audible, and Audnexus.
  """

  use Boundary,
    type: :strict,
    deps: [Jason, Floki, Logger, Req],
    exports: [{Audible, []}, {Audnexus, []}, {GoodReads, []}, Marionette]

  defdelegate web_scraping_available?, to: AmbryScraping.Marionette
end
