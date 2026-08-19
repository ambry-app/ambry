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
    exports: [Listener, Query]

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Drain
  alias Ambry.Search.Query

  @results_limit 36

  # Universes are indexed — a book is findable by the universe it belongs to,
  # and the admin picker searches them — but they are left out of user search
  # because there is no public universe page for a result to land on. Adding
  # `:universe` here is the second half of that feature, not this half.
  @user_facing_types [:book, :person, :series]

  @doc """
  Rebuilds the entire index, in the background.

  What the admin's reindex button calls. Not needed for correctness — the
  triggers cover that — but a schema change to what a record holds needs one
  pass over the library, and so does an operator who does not believe us.
  """
  defdelegate reindex_all!, to: Drain

  @doc """
  What the index holds, and whether it is behind. See `Drain.stats/0`.
  """
  defdelegate stats, to: Drain

  @doc """
  Waits for the index to reflect everything written so far. See
  `Ambry.Search.Drain.settle/0`.
  """
  defdelegate settle, to: Drain

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

  User search is `:all` — every word you typed has to appear somewhere — with
  `partial: true` on the last word. The partial is not a search-as-you-type
  affordance here (this page is submitted, not live); it replaces the `ILIKE
  '%…%'` arm this query used to carry beside the tsquery. That arm was
  load-bearing in one direction only: `sander` found Sanderson through the
  substring, never through the tsquery, and dropping it without a prefix
  match would have been a regression.
  """
  def query(query_string) do
    Query.build(query_string, joiner: :all, partial: true, types: @user_facing_types)
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
