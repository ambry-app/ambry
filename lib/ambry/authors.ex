defmodule Ambry.Authors do
  @moduledoc """
  Functions for dealing with Authors.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Authors.Author
  alias Ambry.Repo

  @doc """
  Gets an author and all of their books.

  Books are listed in descending order based on publish date.
  """
  def get_author_with_books!(author_id) do
    books_query = from b in Book, order_by: [desc: b.published]

    Author
    |> preload(books: ^{books_query, [:authors, series_books: :series]})
    |> Repo.get!(author_id)
  end

  @doc """
  Gets an author.
  """
  def get_author!(author_id) do
    Repo.get!(Author, author_id)
  end

  @doc """
  Finds authors that match a query string.
  """
  def search(query) do
    name_query = "%#{query}%"
    query = from a in Author, where: ilike(a.name, ^name_query), limit: 15

    Repo.all(query)
  end
end
