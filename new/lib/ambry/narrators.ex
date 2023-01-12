defmodule Ambry.Narrators do
  @moduledoc """
  Functions for dealing with Narrators.
  """

  import Ambry.SearchUtils
  import Ecto.Query

  alias Ambry.Narrators.Narrator
  alias Ambry.Repo

  @doc """
  Finds narrators that match a query string.

  Returns a list of tuples of the form `{jaro_distance, narrator}`.
  """
  def search(query_string, limit \\ 15) do
    name_query = "%#{query_string}%"
    query = from n in Narrator, where: ilike(n.name, ^name_query), limit: ^limit

    query
    |> preload(:person)
    |> Repo.all()
    |> sort_by_jaro(query_string, :name)
  end

  @doc """
  Returns all narrators for use in `Select` components.
  """
  def for_select do
    query = from n in Narrator, select: {n.name, n.id}, order_by: n.name

    Repo.all(query)
  end
end
