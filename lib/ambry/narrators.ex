defmodule Ambry.Narrators do
  @moduledoc """
  Functions for dealing with Narrators.
  """

  import Ambry.SearchUtils
  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Narrators.Narrator
  alias Ambry.Repo

  @doc """
  Gets a narrators and all of their books.

  Books are listed in descending order based on publish date.
  """
  def get_narrator_with_books!(narrator_id) do
    books_query = from b in Book, order_by: [desc: b.published]

    Narrator
    |> preload(books: ^{books_query, [:authors, series_books: :series]})
    |> Repo.get!(narrator_id)
  end

  @doc """
  Finds narrators that match a query string.

  Returns a list of tuples of the form `{jaro_distance, narrator}`.
  """
  def search(query_string, limit \\ 15) do
    name_query = "%#{query_string}%"
    query = from n in Narrator, where: ilike(n.name, ^name_query), limit: ^limit

    query
    |> preload(:person)
    |> Repo.all()
    |> sort_by_jaro(query_string, :name)
  end
end
