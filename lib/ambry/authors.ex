defmodule Ambry.Authors do
  @moduledoc """
  Functions for dealing with Authors.
  """

  import Ecto.Query

  alias Ambry.Authors.Author
  alias Ambry.Repo

  @doc """
  Returns all authors for use in `Select` components.
  """
  def for_select do
    query = from a in Author, select: {a.name, a.id}, order_by: a.name

    Repo.all(query)
  end

  def find_by_names(names) do
    query = from a in Author, where: a.name in ^names

    query
    |> Repo.all()
    |> Map.new(&{&1.name, &1})
  end
end
