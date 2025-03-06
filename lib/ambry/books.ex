defmodule Ambry.Books do
  @moduledoc """
  Functions for dealing with Books.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Book,
      Series,
      SeriesBook,
      SeriesFlat,
      SeriesBookType,
      SeriesBookType.Type,
      PubSub.BookCreated,
      PubSub.BookUpdated,
      PubSub.BookDeleted,
      PubSub.SeriesCreated,
      PubSub.SeriesUpdated,
      PubSub.SeriesDeleted
    ]

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.BookFlat
  alias Ambry.Books.PubSub.BookCreated
  alias Ambry.Books.PubSub.BookDeleted
  alias Ambry.Books.PubSub.BookUpdated
  alias Ambry.Books.PubSub.SeriesCreated
  alias Ambry.Books.PubSub.SeriesDeleted
  alias Ambry.Books.PubSub.SeriesUpdated
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesFlat
  alias Ambry.Media.Media
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search

  require Logger

  @book_direct_assoc_preloads [:authors, :media, book_authors: [:author], series_books: [:series]]

  def book_standard_preloads, do: @book_direct_assoc_preloads

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
    Repo.aggregate(Book, :count)
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
    Repo.transact(fn ->
      changeset = change_book(%Book{}, attrs)

      with {:ok, book} <- Repo.insert(changeset),
           :ok <- Search.insert(book),
           {:ok, _job} <- broadcast_book_created(book) do
        {:ok, book}
      end
    end)
  end

  defp broadcast_book_created(%Book{} = book) do
    book
    |> BookCreated.new()
    |> PubSub.broadcast_async()
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
    Repo.transact(fn ->
      book = Repo.preload(book, @book_direct_assoc_preloads)
      changeset = change_book(book, attrs)

      with {:ok, updated_book} <- Repo.update(changeset),
           :ok <- Search.update(updated_book),
           {:ok, _job} <- broadcast_book_updated(updated_book) do
        {:ok, updated_book}
      end
    end)
  end

  defp broadcast_book_updated(%Book{} = book) do
    book
    |> BookUpdated.new()
    |> PubSub.broadcast_async()
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
    Repo.transact(fn ->
      changeset = change_book(book)

      with {:ok, deleted_book} <- Repo.delete(changeset),
           :ok <- Search.delete(deleted_book),
           {:ok, _job} <- broadcast_book_deleted(deleted_book) do
        {:ok, deleted_book}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          if Keyword.has_key?(changeset.errors, :media) do
            {:error, :has_media}
          else
            {:error, changeset}
          end
      end
    end)
  end

  defp broadcast_book_deleted(%Book{} = book) do
    book
    |> BookDeleted.new()
    |> PubSub.broadcast_async()
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
    media_query = from m in Media, where: [status: :ready], order_by: {:desc, :published}

    Book
    |> preload([
      :authors,
      series_books: :series,
      media: ^{media_query, [:narrators, book: [:authors, series_books: :series]]}
    ])
    |> Repo.get!(book_id)
  end

  @doc """
  Lists recent books.
  """
  def get_recent_books(offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    query = from b in Book, order_by: [desc: b.inserted_at], offset: ^offset, limit: ^over_limit

    books =
      query
      |> preload([:authors, :media, series_books: :series])
      |> Repo.all()

    books_to_return = Enum.slice(books, 0, limit)

    {books_to_return, books != books_to_return}
  end

  @doc """
  Returns all books for use in `Select` components.
  """
  def books_for_select do
    query = from b in Book, select: {b.title, b.id}, order_by: b.title

    Repo.all(query)
  end

  @doc """
  Returns a description of a book containing its title and author names.
  """
  def get_book_description(%Book{} = book) do
    book = Repo.preload(book, :authors)
    authors = Enum.map_join(book.authors, ", ", & &1.name)

    "#{book.title} • by #{authors}"
  end

  @doc """
  Returns a paginated list of books authored by (or narrated by) the given
  author (or narrator).
  """
  def get_authored_books(author, offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    query =
      from b in Ecto.assoc(author, :books),
        order_by: [desc: b.published],
        offset: ^offset,
        limit: ^over_limit,
        preload: [:authors, :media, series_books: :series]

    books = Repo.all(query)

    books_to_return = Enum.slice(books, 0, limit)

    {books_to_return, books != books_to_return}
  end

  @series_direct_assoc_preloads [series_books: [book: [:media, :authors]]]

  def series_standard_preloads, do: @series_direct_assoc_preloads

  @doc """
  Returns a limited list of series and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_series()
      {[%SeriesFlat{}, ...], true}
  """
  def list_series(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ [asc: :name]) do
    over_limit = limit + 1

    series =
      offset
      |> SeriesFlat.paginate(over_limit)
      |> SeriesFlat.filter(filters)
      |> SeriesFlat.order(order)
      |> Repo.all()

    series_to_return = Enum.slice(series, 0, limit)

    {series_to_return, series != series_to_return}
  end

  @doc """
  Returns the number of series.

  ## Examples

      iex> count_series()
      1
  """
  @spec count_series :: integer()
  def count_series do
    Repo.aggregate(Series, :count)
  end

  @doc """
  Gets a single series.

  Raises `Ecto.NoResultsError` if the Series does not exist.

  ## Examples

      iex> get_series!(123)
      %Series{}

      iex> get_series!(456)
      ** (Ecto.NoResultsError)
  """
  def get_series!(id) do
    Series
    |> preload(^@series_direct_assoc_preloads)
    |> Repo.get!(id)
  end

  @doc """
  Creates a series.

  ## Examples

      iex> create_series(%{field: value})
      {:ok, %Series{}}

      iex> create_series(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def create_series(attrs) do
    Repo.transact(fn ->
      changeset = Series.changeset(%Series{}, attrs)

      with {:ok, series} <- Repo.insert(changeset),
           :ok <- Search.insert(series),
           {:ok, _job} <- broadcast_series_created(series) do
        {:ok, series}
      end
    end)
  end

  defp broadcast_series_created(%Series{} = series) do
    series
    |> SeriesCreated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a series.

  ## Examples

      iex> update_series(series, %{field: new_value})
      {:ok, %Series{}}

      iex> update_series(series, %{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def update_series(%Series{} = series, attrs) do
    Repo.transact(fn ->
      changeset = Series.changeset(series, attrs)

      with {:ok, updated_series} <- Repo.update(changeset),
           :ok <- Search.update(updated_series),
           {:ok, _job} <- broadcast_series_updated(updated_series) do
        {:ok, updated_series}
      end
    end)
  end

  defp broadcast_series_updated(%Series{} = series) do
    series
    |> SeriesUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a series.

  ## Examples

      iex> delete_series(series)
      {:ok, %Series{}}

      iex> delete_series(series)
      {:error, %Ecto.Changeset{}}
  """
  def delete_series(%Series{} = series) do
    Repo.transact(fn ->
      changeset = change_series(series)

      with {:ok, deleted_series} <- Repo.delete(changeset),
           :ok <- Search.delete(deleted_series),
           {:ok, _job} <- broadcast_series_deleted(deleted_series) do
        {:ok, deleted_series}
      end
    end)
  end

  defp broadcast_series_deleted(%Series{} = series) do
    series
    |> SeriesDeleted.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking series changes.

  ## Examples

      iex> change_series(series)
      %Ecto.Changeset{data: %Series{}}
  """
  def change_series(%Series{} = series, attrs \\ %{}) do
    Series.changeset(series, attrs)
  end

  @doc """
  Gets a series and all of its books.

  Books are listed in ascending order based on series book number.
  """
  def get_series_with_books!(series_id) do
    Series
    |> preload(series_books: [book: [:authors, :media, series_books: :series]])
    |> Repo.get!(series_id)
  end

  @doc """
  Returns all series for use in `Select` components.
  """
  def series_for_select do
    query = from s in Series, select: {s.name, s.id}, order_by: s.name

    Repo.all(query)
  end
end
