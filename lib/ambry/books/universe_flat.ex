defmodule Ambry.Books.UniverseFlat do
  @moduledoc """
  A flattened view of universes.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Search.Query

  schema "universes_flat" do
    field :name, :string
    field :books, :integer
    field :thumbnails, {:array, :string}

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    from u in query,
      where: u.id in subquery(Query.ids(search_string, :universe))
  end
end
