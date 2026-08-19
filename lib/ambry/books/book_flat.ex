defmodule Ambry.Books.BookFlat do
  @moduledoc """
  A flattened view of books.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Books.SeriesBookType
  alias Ambry.People.PersonName
  alias Ambry.Search.Query

  schema "books_flat" do
    field :title, :string
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :thumbnails, {:array, :string}
    field :authors, {:array, PersonName.Type}
    field :series, {:array, SeriesBookType.Type}
    field :universes, :string
    field :media, :integer

    # deprecated
    field :image_path, :string
    field :has_description, :boolean

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    from b in query,
      where: b.id in subquery(Query.ids(search_string, :book))
  end
end
