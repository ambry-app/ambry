defmodule Ambry.Narrators do
  @moduledoc """
  Functions for dealing with Narrators.
  """

  import Ecto.Query

  alias Ambry.Narrators.Narrator
  alias Ambry.Repo

  @doc """
  Gets a single narrator.

  Raises `Ecto.NoResultsError` if the Narrator does not exist.
  """
  def get_narrator!(id), do: Narrator |> preload(:person) |> Repo.get!(id)

  @doc """
  Returns all narrators for use in `Select` components.
  """
  def for_select do
    query = from n in Narrator, select: {n.name, n.id}, order_by: n.name

    Repo.all(query)
  end
end
