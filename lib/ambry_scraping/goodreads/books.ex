defmodule AmbryScraping.GoodReads.Books do
  @moduledoc """
  GoodReads web-scraping API for books
  """

  alias AmbryScraping.GoodReads.Books.EditionDetails
  alias AmbryScraping.GoodReads.Books.Editions
  alias AmbryScraping.GoodReads.Books.Search

  @doc """
  Returns book search results for a given query

  ## Examples

      iex> search("lord of the rings")
      {:ok,
       %AmbryScraping.GoodReads.Books.Search{
         query: "lord of the rings",
         results: [
           %AmbryScraping.GoodReads.Books.Search.Book{
             id: "work:1540236-the-hobbit",
             title: "The Hobbit (The Lord of the Rings, #0)",
             contributors: [
               %AmbryScraping.GoodReads.Books.Search.Contributor{
                 id: "author:656983.J_R_R_Tolkien",
                 name: "J.R.R. Tolkien",
                 type: "author"
               }
             ]
           },
           %AmbryScraping.GoodReads.Books.Search.Book{
             id: "work:3204327-the-lord-of-the-rings-the-fellowship-of-the-ring",
             title: "The Fellowship of the Ring (The Lord of the Rings, #1)",
             contributors: [
               %AmbryScraping.GoodReads.Books.Search.Contributor{
                 id: "author:656983.J_R_R_Tolkien",
                 name: "J.R.R. Tolkien",
                 type: "author"
               }
             ]
           },
           ...
         ]
       }
  """
  defdelegate search(query), to: Search

  ###

  @doc """
  Returns list of editions for a given book
  """
  defdelegate editions(work_id), to: Editions

  @doc """
  Returns the details for a given edition of a book
  """
  defdelegate edition_details(edition_id), to: EditionDetails
end
