defmodule Ambry.Books.UniverseFlat do
  @moduledoc """
  A flattened view of universes.
  """

  use Ambry.Repo.FlatSchema

  schema "universes_flat" do
    field :name, :string
    field :books, :integer
    field :thumbnails, {:array, :string}

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from u in query, where: ilike(u.name, ^search_string)
  end
end
