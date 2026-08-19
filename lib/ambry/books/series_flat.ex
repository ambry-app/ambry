defmodule Ambry.Books.SeriesFlat do
  @moduledoc """
  A flattened view of series.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.People.PersonName
  alias Ambry.Search.Query

  schema "series_flat" do
    field :name, :string
    field :books, :integer
    field :media, :integer
    field :thumbnails, {:array, :string}
    field :authors, {:array, PersonName.Type}

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    from s in query,
      where: s.id in subquery(Query.ids(search_string, :series))
  end
end
