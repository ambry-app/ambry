defmodule Ambry.Authors do
  @moduledoc """
  Functions for dealing with Authors.
  """

  import Ambry.SearchUtils
  import Ecto.Query

  alias Ambry.Authors.Author
  alias Ambry.Repo

  @doc """
  Gets an author.
  """
  def get_author!(author_id) do
    Repo.get!(Author, author_id)
  end

  @doc """
  Finds authors that match a query string.

  Returns a list of tuples of the form `{jaro_distance, author}`.
  """
  def search(query_string, limit \\ 15) do
    name_query = "%#{query_string}%"
    query = from a in Author, where: ilike(a.name, ^name_query), limit: ^limit

    query
    |> preload(:person)
    |> Repo.all()
    |> sort_by_jaro(query_string, :name)
  end

  @doc """
  Returns all authors for use in `Select` components.
  """
  def for_select do
    query = from a in Author, select: {a.name, a.id}, order_by: a.name

    Repo.all(query)
  end
end
