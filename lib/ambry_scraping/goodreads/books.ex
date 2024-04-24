defmodule AmbryScraping.GoodReads.Books do
  @moduledoc false

  alias AmbryScraping.GoodReads.Books.EditionDetails
  alias AmbryScraping.GoodReads.Books.Editions
  alias AmbryScraping.GoodReads.Books.Search

  def search(query), do: Search.search(query)
  def editions(work_id), do: Editions.editions(work_id)
  def edition_details(edition_id), do: EditionDetails.edition_details(edition_id)
end
