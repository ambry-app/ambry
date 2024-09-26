defmodule Ambry.Sync do
  @moduledoc """
  Sync module
  """

  use Boundary, deps: [Ambry]

  import Ecto.Query

  alias Ambry.Deletions.Deletion
  alias Ambry.Repo

  def changes_since(queryable, nil), do: {:ok, Repo.all(queryable)}

  def changes_since(queryable, since),
    do: {:ok, Repo.all(from q in queryable, where: q.updated_at >= ^since)}

  def deletions_since(nil), do: {:ok, []}

  def deletions_since(since),
    do: {:ok, Repo.all(from d in Deletion, where: d.deleted_at >= ^since)}
end
