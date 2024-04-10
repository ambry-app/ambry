defmodule AmbryScraping.GoodReads do
  @moduledoc false

  alias AmbryScraping.GoodReads.Authors
  alias AmbryScraping.GoodReads.Books

  defdelegate author_details(id), to: Authors, as: :details
  defdelegate search_authors(query), to: Authors, as: :search

  defdelegate search_books(query), to: Books, as: :search
  defdelegate book_editions(work_id), to: Books, as: :editions
  defdelegate book_edition_details(edition_id), to: Books, as: :edition_details
end
