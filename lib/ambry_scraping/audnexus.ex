defmodule AmbryScraping.Audnexus do
  @moduledoc false

  use Boundary, deps: [AmbryScraping.Image]

  alias AmbryScraping.Audnexus.Authors
  alias AmbryScraping.Audnexus.Books

  defdelegate author_details(id), to: Authors, as: :details
  defdelegate search_authors(query), to: Authors, as: :search

  defdelegate book_chapters(asin), to: Books, as: :chapters
end
