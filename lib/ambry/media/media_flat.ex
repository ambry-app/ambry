defmodule Ambry.Media.MediaFlat do
  @moduledoc """
  A flattened view of media.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Books.SeriesBookType
  alias Ambry.People.PersonName

  schema "media_flat" do
    field :status, Ecto.Enum, values: [:pending, :processing, :error, :ready]
    field :full_cast, :boolean
    field :abridged, :boolean
    field :duration, :decimal
    field :chapters, :integer
    field :book, :string
    field :thumbnail, :string
    field :series, {:array, SeriesBookType.Type}
    field :universe, :string
    field :authors, {:array, PersonName.Type}
    field :narrators, {:array, PersonName.Type}
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :publisher, :string
    field :has_description, :boolean

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from m in query,
      where:
        ilike(m.book, ^search_string) or ilike(m.universe, ^search_string) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ?)",
            m.series,
            ^search_string
          ) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ? OR (elem).person_name ILIKE ?)",
            m.authors,
            ^search_string,
            ^search_string
          ) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ? OR (elem).person_name ILIKE ?)",
            m.narrators,
            ^search_string,
            ^search_string
          )
  end

  def filter(query, :status, status), do: from(p in query, where: [status: ^status])
  def filter(query, :full_cast, full_cast?), do: from(p in query, where: [full_cast: ^full_cast?])
  def filter(query, :abridged, abridged?), do: from(p in query, where: [abridged: ^abridged?])

  def filter(query, :has_chapters, true), do: from(p in query, where: p.chapters > 0)
  def filter(query, :has_chapters, false), do: from(p in query, where: p.chapters == 0)
end
