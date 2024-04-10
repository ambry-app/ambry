defmodule AmbryScraping do
  @moduledoc false
  use Boundary,
    deps: [],
    exports: [
      Audible,
      Audible.Products.Product,
      Audnexus,
      GoodReads,
      GoodReads.Books.Editions.Edition,
      GoodReads.Books.Search.Book,
      GoodReads.PublishedDate
    ]

  alias AmbryScraping.Marionette.Connection

  def web_scraping_available? do
    Connection
    |> Process.whereis()
    |> then(fn
      nil -> false
      pid -> Process.alive?(pid)
    end)
  end
end
