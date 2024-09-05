defmodule Ambry.Books.BookFlat do
  @moduledoc """
  A flattened view of books.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Books.SeriesBookType
  alias Ambry.People.PersonName

  schema "books_flat" do
    field :title, :string
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :image_path, :string
    field :authors, {:array, PersonName.Type}
    field :series, {:array, SeriesBookType.Type}
    field :universe, :string
    field :media, :integer
    field :has_description, :boolean

    timestamps(type: :utc_datetime)
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
