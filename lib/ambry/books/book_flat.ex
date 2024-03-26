defmodule Ambry.Books.BookFlat do
  @moduledoc """
  A flattened view of books.
  """

  use Ambry.FlatSchema

  alias Ambry.Ecto.Types.PersonName
  alias Ambry.Ecto.Types.SeriesBook

  schema "books_flat" do
    field :title, :string
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :image_path, :string
    field :authors, {:array, PersonName}
    field :series, {:array, SeriesBook}
    field :universe, :string
    field :media, :integer
    field :has_description, :boolean

    timestamps()
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from b in query,
      where:
        ilike(b.title, ^search_string) or ilike(b.universe, ^search_string) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ?)",
            b.series,
            ^search_string
          ) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ? OR (elem).person_name ILIKE ?)",
            b.authors,
            ^search_string,
            ^search_string
          )
  end
end
