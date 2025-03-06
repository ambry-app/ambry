defmodule Ambry.Search do
  @moduledoc """
  A context for aggregate search across books, authors, narrators and series.
  """

  use Boundary,
    deps: [
      Ambry.Books,
      Ambry.Media,
      Ambry.People,
      Ambry.PubSub,
      Ambry.Repo
    ],
    exports: [IndexManager]

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series, as: SeriesSchema
  alias Ambry.Media.Media
  alias Ambry.People
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Index
  alias Ambry.Search.Record

  @results_limit 36

  defdelegate refresh_entire_index!, to: Index

  def insert(%Person{id: id}) do
    Index.insert!(:person, id)
  rescue
    _ -> :error
  end

  def insert(%Media{id: id}) do
    Index.insert!(:media, id)
  rescue
    _ -> :error
  end

  def update(%Person{id: id}) do
    Index.update!(:person, id)
  rescue
    _ -> :error
  end

  def update(%Media{id: id}) do
    Index.update!(:media, id)
  rescue
    _ -> :error
  end

  def delete(%Person{id: id}) do
    Index.delete!(:person, id)
  rescue
    _ -> :error
  end

  def delete(%Media{id: id}) do
    Index.delete!(:media, id)
  rescue
    _ -> :error
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

  def query(query_string) do
    like = "%#{query_string}%"

    from record in Record,
      where:
        fragment("? @@ plainto_tsquery(?)", record.search_vector, ^query_string) or
          ilike(record.primary, ^like) or ilike(record.secondary, ^like) or
          ilike(record.tertiary, ^like),
      order_by: [
        {:desc,
         fragment("ts_rank_cd(?, plainto_tsquery(?))", record.search_vector, ^query_string)},
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

  defp fetch_series(ids, preload),
    do: fetch(from(s in SeriesSchema, where: s.id in ^ids), preload)

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
