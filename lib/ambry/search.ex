defmodule Ambry.Search do
  @moduledoc """
  A context for aggregate search across books, authors, narrators and series.
  """

  import Ecto.Query

  alias Ambry.{Authors, Books, Narrators, Series}

  alias Ambry.Books.Book
  alias Ambry.People.Person
  alias Ambry.Repo
  alias Ambry.Search.Record
  alias Ambry.Series.Series, as: SeriesSchema

  # Old search implementation (used in web app)

  def search(query) do
    authors = Authors.search(query, 10)
    books = Books.search(query, 10)
    narrators = Narrators.search(query, 10)
    series = Series.search(query, 10)

    [
      {:authors, authors},
      {:books, books},
      {:narrators, narrators},
      {:series, series}
    ]
    |> Enum.reject(&(elem(&1, 1) == []))
    |> Enum.sort_by(
      fn {_label, items} ->
        items
        |> Enum.map(&elem(&1, 0))
        |> average()
      end,
      :desc
    )
  end

  defp average(floats) do
    Enum.sum(floats) / length(floats)
  end

  # New search implementation (used by graphql)

  def new_search(query_string) do
    query_string
    |> query()
    |> all()
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

  def all(query) do
    references =
      query
      |> Repo.all()
      |> Enum.map(& &1.reference)

    {book_ids, person_ids, series_ids} = partition_references(references)

    books = fetch_books(book_ids)
    people = fetch_people(person_ids)
    series = fetch_series(series_ids)

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

  defp fetch_books(ids) do
    query = from(b in Book, where: b.id in ^ids)
    query |> Repo.all() |> Map.new(&{&1.id, &1})
  end

  defp fetch_people(ids) do
    query = from(p in Person, where: p.id in ^ids)
    query |> Repo.all() |> Map.new(&{&1.id, &1})
  end

  defp fetch_series(ids) do
    query = from(s in SeriesSchema, where: s.id in ^ids)
    query |> Repo.all() |> Map.new(&{&1.id, &1})
  end

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
