defmodule Ambry.Series do
  @moduledoc """
  Functions for dealing with Series.
  """

  import Ambry.SearchUtils
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

  Returns a list of tuples of the form `{jaro_distance, series}`.
  """
  def search(query_string, limit \\ 15) do
    name_query = "%#{query_string}%"
    query = from s in Series, where: ilike(s.name, ^name_query), limit: ^limit
    series_book_query = from sb in SeriesBook, order_by: [asc: sb.book_number]

    query
    |> preload(series_books: ^{series_book_query, [book: [:authors, series_books: :series]]})
    |> Repo.all()
    |> sort_by_jaro(query_string, :name)
  end
end
