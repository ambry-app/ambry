defmodule GoodReads.Books do
  @moduledoc """
  GoodReads web-scraping API for books
  """

  alias GoodReads.Books.{Details, Edition, Search}

  @doc """
  Returns book search results for a given query

  ## Examples

      iex> search("lord of the rings")
      [
        %GoodReads.Books.Search.Book{
          id: "1540236-the-hobbit",
          title: "The Hobbit",
          authors: [
            %GoodReads.Books.Search.Contributor{
              id: "656983.J_R_R_Tolkien",
              name: "J.R.R. Tolkien",
              type: "author"
            }
          ],
          series: %GoodReads.Books.Search.Series{
            name: "The Lord of the Rings",
            number: "0"
          },
          most_reviewed_edition_id: "5907.The_Hobbit"
        },
        %GoodReads.Books.Search.Book{
          id: "3204327-the-lord-of-the-rings-the-fellowship-of-the-ring",
          title: "The Fellowship of the Ring",
          authors: [
            %GoodReads.Books.Search.Contributor{
              id: "656983.J_R_R_Tolkien",
              name: "J.R.R. Tolkien",
              type: "author"
            }
          ],
          series: %GoodReads.Books.Search.Series{
            name: "The Lord of the Rings",
            number: "1"
          },
          most_reviewed_edition_id: "61215351-the-fellowship-of-the-ring"
        },
        ...
      ]
  """
  defdelegate search(query), to: Search

  ###

  @doc """
  Returns details for a given book
  """
  defdelegate details(id), to: Details

  @doc """
  Returns details for a given edition
  """
  defdelegate edition(edition_id), to: Edition
end
