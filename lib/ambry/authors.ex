defmodule Ambry.Authors do
  @moduledoc """
  Functions for dealing with Authors.
  """

  import Ecto.Query

  alias Ambry.Authors.Author
  alias Ambry.Repo

  @doc """
  Gets a single author.

  Raises `Ecto.NoResultsError` if the Author does not exist.
  """
  def get_author!(id), do: Author |> preload(:person) |> Repo.get!(id)

  @doc """
  Returns all authors for use in `Select` components.
  """
  def for_select do
    query = from a in Author, select: {a.name, a.id}, order_by: a.name

    Repo.all(query)
  end
end
