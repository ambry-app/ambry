defmodule Ambry.Search do
  @moduledoc """
  A context for aggregate search across books, authors, narrators and series.

  ## The index maintains itself

  Nothing calls this module to keep the index current. Row triggers on the
  library's tables fill `Ambry.Search.Queue`, `Ambry.Search.Listener` notices
  and `Ambry.Search.Drain` rebuilds what changed. That is a deliberate
  inversion: index maintenance used to be twelve hand-placed calls in the
  contexts' `with` chains, and any write by another path — the inbox importer
  most of all, which its boundary forbids from calling this module — drifted
  the index silently. The server rebuilt the whole index on every boot to hide
  it.

  A write is therefore reflected in search a moment after it commits, not
  within the same call. Nothing in the app may depend on that moment being
  zero; `settle/0` exists so tests don't have to.
  """

  use Boundary,
    deps: [
      Ambry.Books,
      Ambry.Media,
      Ambry.People,
      Ambry.PubSub,
      Ambry.Repo
    ],
    exports: [Listener]

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Drain
  alias Ambry.Search.Record

  @results_limit 36

  @doc """
  Rebuilds the entire index, from scratch.

  What the admin's reindex button calls. Not needed for correctness — the
  triggers cover that — but a schema change to what a record holds needs one
  pass over the library, and so does an operator who does not believe us.
  """
  defdelegate reindex_all!, to: Drain

  @doc """
  Waits for the index to reflect everything written so far.

  In production this is a no-op: the listener has already drained, or is about
  to, and no caller should be waiting on it. In test there is no listener —
  the SQL sandbox holds every write in an uncommitted transaction, so a
  `NOTIFY` is never delivered and an Oban job never runs — so this drains
  inline. It is called by the read paths rather than by tests, so that a test
  which writes and then searches sees what the running system would a
  millisecond later, without having to know that a queue exists.
  """
  if Application.compile_env(:ambry, [__MODULE__, :settle_inline], false) do
    def settle do
      {:ok, _count} = Drain.run()
      :ok
    end
  else
    def settle, do: :ok
  end

  def search(query_string) do
    query_string
    |> query()
    |> limit(@results_limit)
    |> all(
      books_preload: Books.book_standard_preloads(),
      series_preload: Books.series_standard_preloads(),
      people_preload: People.person_standard_preloads()
    )
  end

  def find_first(query_string, type) do
    query_string
    |> search()
    |> Enum.find(fn
      %^type{} -> true
      _else -> false
    end)
  end

  @doc """
  The index, narrowed to what matches `query_string`, as a composable
  queryable.

  Every read path in the app composes from here — `search/1`, the GraphQL
  connection — which is why `settle/0` is called here rather than in each of
  them. Outside test it compiles to nothing.

  Both sides parse with `ambry_english`, so a query folds accents the same way
  the stored vector did. The config is passed explicitly rather than leaning
  on `default_text_search_config`, which is session state.
  """
  def query(query_string) do
    :ok = settle()

    like = "%#{query_string}%"

    from record in Record,
      where:
        fragment("? @@ plainto_tsquery('ambry_english', ?)", record.search_vector, ^query_string) or
          ilike(record.primary, ^like) or ilike(record.secondary, ^like) or
          ilike(record.tertiary, ^like),
      order_by: [
        {:desc,
         fragment(
           "ts_rank_cd(?, plainto_tsquery('ambry_english', ?))",
           record.search_vector,
           ^query_string
         )},
        {:desc,
         fragment(
           """
           CASE
             WHEN ? ILIKE ? THEN 1
             WHEN ? ILIKE ? THEN 0.4
             WHEN ? ILIKE ? THEN 0.2
             ELSE 0
           END
           """,
           record.primary,
           ^like,
           record.secondary,
           ^like,
           record.tertiary,
           ^like
         )},
        {:desc,
         fragment(
           """
           COALESCE(similarity(?, ?), 0) +
           COALESCE(similarity(?, ?), 0) +
           COALESCE(similarity(?, ?), 0)
           """,
           record.primary,
           ^query_string,
           record.secondary,
           ^query_string,
           record.tertiary,
           ^query_string
         )}
      ]
  end

  def all(query, opts \\ []) do
    references =
      query
      |> Repo.all()
      |> Enum.map(& &1.reference)

    {book_ids, person_ids, series_ids} = partition_references(references)

    books = fetch_books(book_ids, opts[:books_preload])
    people = fetch_people(person_ids, opts[:people_preload])
    series = fetch_series(series_ids, opts[:series_preload])

    recombine(references, books, people, series)
  end

  defp partition_references(references) do
    Enum.reduce(references, {[], [], []}, &do_partition/2)
  end

  defp do_partition(%{type: :book, id: id}, {books, people, series}),
    do: {[id | books], people, series}

  defp do_partition(%{type: :person, id: id}, {books, people, series}),
    do: {books, [id | people], series}

  defp do_partition(%{type: :series, id: id}, {books, people, series}),
    do: {books, people, [id | series]}

  defp fetch_books(ids, preload), do: fetch(from(b in Book, where: b.id in ^ids), preload)

  defp fetch_people(ids, preload), do: fetch(from(p in Person, where: p.id in ^ids), preload)

  defp fetch_series(ids, preload), do: fetch(from(s in Series, where: s.id in ^ids), preload)

  defp fetch(query, preload) do
    query
    |> maybe_add_preload(preload)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp maybe_add_preload(query, nil), do: query
  defp maybe_add_preload(query, preload), do: from(q in query, preload: ^preload)

  defp recombine(references, books, people, series) do
    Enum.map(references, fn reference ->
      case reference do
        %{type: :book, id: id} -> Map.fetch!(books, id)
        %{type: :person, id: id} -> Map.fetch!(people, id)
        %{type: :series, id: id} -> Map.fetch!(series, id)
      end
    end)
  end
end
