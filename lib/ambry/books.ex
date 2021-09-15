defmodule Ambry.Books do
  @moduledoc """
  Functions for dealing with Books.
  """

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Media.Media
  alias Ambry.Repo

  @doc """
  Gets a book and all of its media.
  """
  def get_book_with_media!(book_id) do
    media_query = from m in Media, where: [status: :ready]

    Book
    |> preload([:authors, media: ^{media_query, [:narrators]}, series_books: :series])
    |> Repo.get!(book_id)
  end

  @doc """
  Lists recent books.
  """
  def get_recent_books!(offset \\ 0, limit \\ 10) do
    query = from b in Book, order_by: [desc: b.inserted_at], offset: ^offset, limit: ^limit

    query
    |> preload([:authors, series_books: :series])
    |> Repo.all()
  end

  @doc """
  Gets a book.
  """
  def get_book!(book_id) do
    Repo.get!(Book, book_id)
  end

  @doc """
  Finds books that match a query string.
  """
  def search(query) do
    title_query = "%#{query}%"
    query = from b in Book, where: ilike(b.title, ^title_query), limit: 15

    Repo.all(query)
  end

  @doc """
  Creates a new book.
  """
  def create_book(params) do
    changeset = change_book(params)

    Repo.insert(changeset)
  end

  @doc """
  Returns a changeset for a book.
  """
  def change_book(book \\ %Book{}, params) do
    Book.changeset(book, params)
  end
end
