defmodule AmbryScraping.Audible do
  @moduledoc false

  alias AmbryScraping.Audible.Authors
  alias AmbryScraping.Audible.Products

  defdelegate author_details(id), to: Authors, as: :details
  defdelegate search_authors(query), to: Authors, as: :search

  defdelegate search_books(query), to: Products, as: :search
end
