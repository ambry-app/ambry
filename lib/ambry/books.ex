defmodule Ambry.Books do
  @moduledoc """
  Functions for dealing with Books.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Book,
      BookUniverse,
      Series,
      SeriesBook,
      SeriesFlat,
      SeriesBookType,
      SeriesBookType.Type,
      Universe,
      UniverseFlat,
      PubSub.BookCreated,
      PubSub.BookUpdated,
      PubSub.BookDeleted,
      PubSub.SeriesCreated,
      PubSub.SeriesUpdated,
      PubSub.SeriesDeleted,
      PubSub.UniverseCreated,
      PubSub.UniverseUpdated,
      PubSub.UniverseDeleted
    ]

  import Ambry.Utils, only: [series_credit: 1]
  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.BookFlat
  alias Ambry.Books.PubSub.BookCreated
  alias Ambry.Books.PubSub.BookDeleted
  alias Ambry.Books.PubSub.BookUpdated
  alias Ambry.Books.PubSub.SeriesCreated
  alias Ambry.Books.PubSub.SeriesDeleted
  alias Ambry.Books.PubSub.SeriesUpdated
  alias Ambry.Books.PubSub.UniverseCreated
  alias Ambry.Books.PubSub.UniverseDeleted
  alias Ambry.Books.PubSub.UniverseUpdated
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesFlat
  alias Ambry.Books.Universe
  alias Ambry.Books.UniverseFlat
  alias Ambry.Ecto.NameSearch
  alias Ambry.Media.Media
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search

  @book_direct_assoc_preloads [
    :authors,
    :media,
    :universes,
    book_authors: [:author],
    series_books: [:series],
    book_universes: [:universe]
  ]

  def book_standard_preloads, do: @book_direct_assoc_preloads

  @doc """
  The values a library naming template renders from.

  A folder can only sit under one author, so `author` and `series` resolve to
  the **primary** credit — position 0, which the operator controls from the
  book form. That designation is the entire reason credits carry a position.

  Needs `book_authors: [:author]` and `series_books: [:series]` loaded, and
  `media_narrators: [:narrator]` on the media; anything not loaded simply
  resolves to nothing rather than raising, since a missing series is a normal
  state and the template collapses empty segments anyway.
  """
  def naming_values(%Book{} = book, %Media{} = media) do
    primary_series = primary(book.series_books)

    %{
      author: book.book_authors |> primary() |> credit_name(:author),
      narrator: media.media_narrators |> primary() |> credit_name(:narrator),
      series: primary_series && primary_series.series && primary_series.series.name,
      series_book_number: primary_series && book_number(primary_series.book_number),
      # the media's own title wins when set — that's what the title override
      # is for — and the book's title is the fallback
      title: presence(media.title) || book.title,
      year: year(media.published || book.published)
    }
  end

  # Position 0 is the operator's designated primary. The list arrives in
  # position order via `preload_order`, but this is explicit rather than
  # trusting whatever order a caller happened to load it in.
  defp primary(entries) when is_list(entries),
    do: Enum.min_by(entries, & &1.position, fn -> nil end)

  defp primary(_not_loaded), do: nil

  defp credit_name(nil, _key), do: nil

  defp credit_name(entry, key) do
    case Map.get(entry, key) do
      %{name: name} -> name
      _not_loaded -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(value) when is_binary(value), do: if(String.trim(value) != "", do: value)

  defp year(nil), do: nil
  defp year(%Date{year: year}), do: year

  # Book numbers are decimals so half-books (1.5) work, but "1.0" in a folder
  # name is noise.
  defp book_number(nil), do: nil

  defp book_number(decimal) do
    if Decimal.equal?(decimal, Decimal.round(decimal, 0)),
      do: decimal |> Decimal.round(0) |> Decimal.to_string(),
      else: Decimal.to_string(decimal, :normal)
  end

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
  Books ranked by how many of the given keywords they match.

  A different question from `list_books/4`'s search, which asks whether one
  whole string appears inside one field. That is right for a person typing and
  wrong for matching a file against the library, where the file's idea of the
  title routinely isn't the library's — a term that misses should cost
  nothing, and a term that hits should earn a point.
  """
  @spec match_books([String.t()], pos_integer()) :: [struct()]
  def match_books(terms, limit \\ 10) do
    terms |> BookFlat.by_keywords(limit) |> Repo.all()
  end

  @doc """
  Splits a phrase into the keywords `match_books/2` should be given.
  """
  @spec match_keywords(String.t() | nil) :: [String.t()]
  defdelegate match_keywords(phrase), to: BookFlat, as: :keywords

  @doc """
  Returns the number of books, under the same filters `list_books/4` lists
  with — so a list can say what page it is of.

  ## Examples

      iex> count_books()
      1

  """
  @spec count_books(map()) :: integer()
  def count_books(filters \\ %{}) do
    filters |> BookFlat.count_query() |> Repo.one()
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

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def create_book(attrs \\ %{}, opts \\ []) do
    Repo.transact(fn ->
      changeset = Book.changeset(%Book{}, attrs, opts)

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

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def update_book(%Book{} = book, attrs, opts \\ []) do
    Repo.transact(fn ->
      book = Repo.preload(book, @book_direct_assoc_preloads)
      changeset = Book.changeset(book, attrs, opts)

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
      media:
        ^{media_query, [:narrators, :recording_group, book: [:authors, series_books: :series]]}
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
  Books matching what somebody typed into a picker, as rich options: cover,
  title, and the authors — the fact that tells two same-titled books apart.

  **Keyword-scored, not substring-matched** (`BookFlat.by_keywords/2`), so
  "sanderson kings" finds The Way of Kings and a term that misses costs
  nothing. That search was built for matching a file against the library and
  it is the better answer here too: a person typing knows the author's name
  more often than they know the exact title.

  With nothing typed, the first page by title — a box that has just been
  focused should show what is there, not nothing.
  """
  def search_books(phrase, limit) do
    case match_keywords(phrase) do
      [] -> BookFlat |> order_by(asc: :title) |> limit(^limit)
      terms -> BookFlat.by_keywords(terms, limit)
    end
    |> Repo.all()
    |> Enum.map(&book_option/1)
  end

  @doc """
  One book as a picker option, or nil.

  What lets a picker name the book it is already holding. The preloaded list
  it replaced was providing this silently, which is most of why it was
  preloaded at all.
  """
  def book_option(nil), do: nil
  def book_option(""), do: nil

  def book_option(id) when is_binary(id) or is_integer(id) do
    case Repo.get(BookFlat, id) do
      nil -> nil
      book -> book_option(book)
    end
  end

  def book_option(%BookFlat{} = book) do
    %{
      id: book.id,
      label: book.title,
      # Where it sits, muted, on the label's own line — the one fact that
      # tells two books with the same title apart at a glance.
      trailer: series_credit(book.series),
      image: List.first(book.thumbnails || []),
      detail: book_select_detail(book)
    }
  end

  defp book_select_detail(%BookFlat{authors: authors}) do
    case Enum.map(authors || [], & &1.name) do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  @doc """
  Returns a description of a book containing its title and author names.
  """
  def get_book_description(%Book{} = book) do
    book = Repo.preload(book, :authors)
    authors = Enum.map_join(book.authors, ", ", & &1.name)

    "#{book.title} by #{authors}"
  end

  @doc """
  Returns a paginated list of books authored by (or narrated by) the given
  author (or narrator).
  """
  def get_authored_books(author, offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    # books with zero ready editions are hidden from users entirely
    # (tile system v2) — filtered here so pagination stays correct
    query =
      from b in Ecto.assoc(author, :books),
        as: :book,
        where:
          exists(from m in Media, where: m.book_id == parent_as(:book).id and m.status == :ready),
        order_by: [desc: b.published],
        offset: ^offset,
        limit: ^over_limit,
        preload: [:authors, :media, series_books: :series]

    books = Repo.all(query)

    books_to_return = Enum.slice(books, 0, limit)

    {books_to_return, books != books_to_return}
  end

  @doc """
  Subscribes to all book CRUD messages.
  """
  def subscribe_to_book_crud_messages do
    :ok = PubSub.subscribe(BookCreated.wildcard_topic())
    :ok = PubSub.subscribe(BookUpdated.wildcard_topic())
    :ok = PubSub.subscribe(BookDeleted.wildcard_topic())
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
  @spec count_series(map()) :: integer()
  def count_series(filters \\ %{}) do
    filters |> SeriesFlat.count_query() |> Repo.one()
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
  Series matching what somebody typed into a picker.
  """
  def search_series(phrase, limit) do
    Series
    |> NameSearch.narrow(:name, phrase, limit)
    |> select([s], {s.name, s.id})
    |> Repo.all()
  end

  @doc """
  One series as a picker option, or nil.
  """
  def series_option(id), do: name_option(Series, id)

  @doc """
  Subscribes to all series CRUD messages.
  """
  def subscribe_to_series_crud_messages do
    :ok = PubSub.subscribe(SeriesCreated.wildcard_topic())
    :ok = PubSub.subscribe(SeriesUpdated.wildcard_topic())
    :ok = PubSub.subscribe(SeriesDeleted.wildcard_topic())
  end

  # Universes
  #
  # NOTE: universes are not in the full-text search index (yet) — deliberate;
  # revisit if searching "Cosmere" ever matters.

  @universe_direct_assoc_preloads [book_universes: [book: [:media, :authors]]]

  def universe_standard_preloads, do: @universe_direct_assoc_preloads

  @doc """
  Returns a limited list of universes and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and
  `limit` to change this. Also can optionally filter by the given `filter`
  string.

  ## Examples

      iex> list_universes()
      {[%UniverseFlat{}, ...], true}
  """
  def list_universes(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ [asc: :name]) do
    over_limit = limit + 1

    universes =
      offset
      |> UniverseFlat.paginate(over_limit)
      |> UniverseFlat.filter(filters)
      |> UniverseFlat.order(order)
      |> Repo.all()

    universes_to_return = Enum.slice(universes, 0, limit)

    {universes_to_return, universes != universes_to_return}
  end

  @doc """
  Returns the number of universes, under the same filters `list_universes/4`
  lists with.
  """
  @spec count_universes(map()) :: integer()
  def count_universes(filters \\ %{}) do
    filters |> UniverseFlat.count_query() |> Repo.one()
  end

  @doc """
  Gets a single universe.

  Raises `Ecto.NoResultsError` if the Universe does not exist.
  """
  def get_universe!(id) do
    Universe
    |> preload(^@universe_direct_assoc_preloads)
    |> Repo.get!(id)
  end

  @doc """
  Creates a universe.
  """
  def create_universe(attrs) do
    Repo.transact(fn ->
      changeset = Universe.changeset(%Universe{}, attrs)

      with {:ok, universe} <- Repo.insert(changeset),
           {:ok, _job} <- broadcast_universe_created(universe) do
        {:ok, universe}
      end
    end)
  end

  defp broadcast_universe_created(%Universe{} = universe) do
    universe
    |> UniverseCreated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a universe.
  """
  def update_universe(%Universe{} = universe, attrs) do
    Repo.transact(fn ->
      changeset = Universe.changeset(universe, attrs)

      with {:ok, updated_universe} <- Repo.update(changeset),
           {:ok, _job} <- broadcast_universe_updated(updated_universe) do
        {:ok, updated_universe}
      end
    end)
  end

  defp broadcast_universe_updated(%Universe{} = universe) do
    universe
    |> UniverseUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a universe.

  Books keep existing — only their universe membership goes away.
  """
  def delete_universe(%Universe{} = universe) do
    Repo.transact(fn ->
      changeset = change_universe(universe)

      with {:ok, deleted_universe} <- Repo.delete(changeset),
           {:ok, _job} <- broadcast_universe_deleted(deleted_universe) do
        {:ok, deleted_universe}
      end
    end)
  end

  defp broadcast_universe_deleted(%Universe{} = universe) do
    universe
    |> UniverseDeleted.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking universe changes.
  """
  def change_universe(%Universe{} = universe, attrs \\ %{}) do
    Universe.changeset(universe, attrs)
  end

  @doc """
  Universes matching what somebody typed into a picker.
  """
  def search_universes(phrase, limit) do
    Universe
    |> NameSearch.narrow(:name, phrase, limit)
    |> select([u], {u.name, u.id})
    |> Repo.all()
  end

  @doc """
  One universe as a picker option, or nil.
  """
  def universe_option(id), do: name_option(Universe, id)

  # Both of the above hold nothing but a name, so their option is the same
  # `{label, id}` pair the picker takes for any simple list.
  defp name_option(_schema, blank) when blank in [nil, ""], do: nil

  defp name_option(schema, id) do
    case Repo.get(schema, id) do
      nil -> nil
      record -> {record.name, record.id}
    end
  end

  @doc """
  Subscribes to all universe CRUD messages.
  """
  def subscribe_to_universe_crud_messages do
    :ok = PubSub.subscribe(UniverseCreated.wildcard_topic())
    :ok = PubSub.subscribe(UniverseUpdated.wildcard_topic())
    :ok = PubSub.subscribe(UniverseDeleted.wildcard_topic())
  end
end
