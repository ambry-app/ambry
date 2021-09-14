defmodule Ambry.Series do
  @moduledoc """
  Functions for dealing with Series.
  """

  import Ecto.Query

  alias Ambry.Series.Series
  alias Ambry.Series.SeriesBook
  alias Ambry.Repo

  @doc """
  Gets a series and all of its books.

  Books are listed in ascending order based on series book number.
  """
  def get_series_with_books!(series_id) do
    series_book_query = from sb in SeriesBook, order_by: [asc: sb.book_number]

    Series
    |> preload(series_books: ^{series_book_query, [book: [:authors, series_books: :series]]})
    |> Repo.get!(series_id)
  end

  @doc """
  Finds series that match a query string.
  """
  def search(query) do
    name_query = "%#{query}%"
    query = from s in Series, where: ilike(s.name, ^name_query), limit: 15

    Repo.all(query)
  end
end
