defmodule Ambry.Books do
  @moduledoc """
  Functions for dealing with Books.
  """

  import Ambry.{FileUtils, SearchUtils}
  import Ecto.Query

  alias Ambry.Books.{Book, BookFlat}
  alias Ambry.Media.Media
  alias Ambry.Repo

  @book_direct_assoc_preloads [book_authors: [:author], series_books: [:series]]

  @doc """
  Returns a limited list of books and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_books()
      {[%BookFlat{}, ...], true}

  """
  def list_books(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ [asc: :title]) do
    over_limit = limit + 1

    books =
      offset
      |> BookFlat.paginate(over_limit)
      |> BookFlat.filter(filters)
      |> BookFlat.order(order)
      |> Repo.all()

    books_to_return = Enum.slice(books, 0, limit)

    {books_to_return, books != books_to_return}
  end

  @doc """
  Returns the number of books.

  ## Examples

      iex> count_books()
      1

  """
  @spec count_books :: integer()
  def count_books do
    Repo.one(from b in Book, select: count(b.id))
  end

  @doc """
  Gets a single book.

  Raises `Ecto.NoResultsError` if the Book does not exist.

  ## Examples

      iex> get_book!(123)
      %Book{}

      iex> get_book!(456)
      ** (Ecto.NoResultsError)

  """
  def get_book!(id) do
    Book
    |> preload(^@book_direct_assoc_preloads)
    |> Repo.get!(id)
  end

  @doc """
  Creates a book.

  ## Examples

      iex> create_book(%{field: value})
      {:ok, %Book{}}

      iex> create_book(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_book(attrs \\ %{}) do
    %Book{}
    |> change_book(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a book.

  ## Examples

      iex> update_book(book, %{field: new_value})
      {:ok, %Book{}}

      iex> update_book(book, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_book(%Book{} = book, attrs) do
    book
    |> Repo.preload(@book_direct_assoc_preloads)
    |> change_book(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a book.

  ## Examples

      iex> delete_book(book)
      :ok

      iex> delete_book(book)
      {:error, :has_media}

      iex> delete_book(book)
      {:error, changeset}

  """
  def delete_book(%Book{} = book) do
    case Repo.delete(change_book(book)) do
      {:ok, book} ->
        maybe_delete_image(book.image_path)
        :ok

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :media) do
          {:error, :has_media}
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking book changes.

  ## Examples

      iex> change_book(book)
      %Ecto.Changeset{data: %Book{}}

  """
  def change_book(%Book{} = book, attrs \\ %{}) do
    Book.changeset(book, attrs)
  end

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
    over_limit = limit + 1

    query = from b in Book, order_by: [desc: b.inserted_at], offset: ^offset, limit: ^over_limit

    books =
      query
      |> preload([:authors, series_books: :series])
      |> Repo.all()

    books_to_return = Enum.slice(books, 0, limit)

    {books_to_return, books != books_to_return}
  end

  @doc """
  Finds books that match a query string.

  Returns a list of tuples of the form `{jaro_distance, book}`.
  """
  def search(query_string, limit \\ 15) do
    title_query = "%#{query_string}%"
    query = from b in Book, where: ilike(b.title, ^title_query), limit: ^limit

    query
    |> preload([:authors, series_books: :series])
    |> Repo.all()
    |> sort_by_jaro(query_string, :title)
  end

  @doc """
  Returns all books for use in `Select` components.
  """
  def for_select do
    query = from b in Book, select: {b.title, b.id}, order_by: b.title

    Repo.all(query)
  end
end
