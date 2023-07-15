defmodule Ambry.Series do
  @moduledoc """
  Functions for dealing with Series.
  """

  import Ambry.Utils
  import Ecto.Query

  alias Ambry.{PubSub, Repo}
  alias Ambry.Series.{Series, SeriesFlat}

  @series_direct_assoc_preloads [series_books: [book: [:authors]]]

  def standard_preloads, do: @series_direct_assoc_preloads

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
    Repo.one(from s in Series, select: count(s.id))
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
    %Series{}
    |> Series.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&PubSub.broadcast_create/1)
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
    series
    |> Series.changeset(attrs)
    |> Repo.update()
    |> tap_ok(&PubSub.broadcast_create/1)
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
    series
    |> Repo.delete()
    |> tap_ok(&PubSub.broadcast_delete/1)
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
    |> preload(series_books: [book: [:authors, series_books: :series]])
    |> Repo.get!(series_id)
  end

  @doc """
  Returns all series for use in `Select` components.
  """
  def for_select do
    query = from s in Series, select: {s.name, s.id}, order_by: s.name

    Repo.all(query)
  end

  def find_by_name(name) do
    query = from a in Series, where: a.name == ^name

    case Repo.one(query) do
      nil -> {:error, :not_found}
      series -> {:ok, series}
    end
  end
end
