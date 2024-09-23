defmodule Ambry.Sync do
  @moduledoc """
  Sync module
  """

  use Boundary, deps: [Ambry]

  import Ecto.Query

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Deletions.Deletion
  alias Ambry.Media.Media
  alias Ambry.People.Person
  alias Ambry.Repo

  def since(since) do
    books = since |> books_query() |> Repo.all()
    series = since |> series_query() |> Repo.all()
    people = since |> people_query() |> Repo.all()
    media = since |> media_query() |> Repo.all()
    deletions = since |> deletions_query() |> Repo.all()
    records = List.flatten([books, series, people, media, deletions])

    {:ok, records}
  end

  defp books_query(nil), do: from(b in Book, order_by: [desc: :updated_at])

  defp books_query(since),
    do: from(b in Book, order_by: [desc: :updated_at], where: b.updated_at >= ^since)

  defp series_query(nil), do: from(s in Series, order_by: [desc: :updated_at])

  defp series_query(since),
    do: from(s in Series, order_by: [desc: :updated_at], where: s.updated_at >= ^since)

  defp people_query(nil), do: from(p in Person, order_by: [desc: :updated_at])

  defp people_query(since),
    do: from(p in Person, order_by: [desc: :updated_at], where: p.updated_at >= ^since)

  defp media_query(nil), do: from(m in Media, order_by: [desc: :updated_at])

  defp media_query(since),
    do: from(m in Media, order_by: [desc: :updated_at], where: m.updated_at >= ^since)

  defp deletions_query(nil), do: from(d in Deletion, order_by: [desc: :deleted_at])

  defp deletions_query(since),
    do: from(d in Deletion, order_by: [desc: :deleted_at], where: d.deleted_at >= ^since)
end
