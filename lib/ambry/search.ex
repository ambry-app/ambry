defmodule Ambry.Search do
  @moduledoc """
  A context for aggregate search across books, authors, narrators and series.
  """

  import Ecto.Query

  alias Ambry.{Authors, Books, Narrators, Series}

  alias Ambry.Media.Media
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

  def query(query_string) do
    from r in Record,
      where: fragment("? @@ plainto_tsquery(?)", r.search_vector, ^query_string),
      order_by: fragment("ts_rank_cd(?, plainto_tsquery(?)) DESC", r.search_vector, ^query_string)
  end

  def all(query) do
    references =
      query
      |> Repo.all()
      |> Enum.map(& &1.reference)

    {media_ids, person_ids, series_ids} = partition_references(references)

    media = fetch_media(media_ids)
    people = fetch_people(person_ids)
    series = fetch_series(series_ids)

    recombine(references, media, people, series)
  end

  defp partition_references(references) do
    Enum.reduce(references, {[], [], []}, &do_partition/2)
  end

  defp do_partition(%{type: :media, id: id}, {media, people, series}),
    do: {[id | media], people, series}

  defp do_partition(%{type: :person, id: id}, {media, people, series}),
    do: {media, [id | people], series}

  defp do_partition(%{type: :series, id: id}, {media, people, series}),
    do: {media, people, [id | series]}

  defp fetch_media(ids) do
    query = from(m in Media, where: m.id in ^ids)
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

  defp recombine(references, media, people, series) do
    Enum.map(references, fn reference ->
      case reference do
        %{type: :media, id: id} -> Map.fetch!(media, id)
        %{type: :person, id: id} -> Map.fetch!(people, id)
        %{type: :series, id: id} -> Map.fetch!(series, id)
      end
    end)
  end
end
