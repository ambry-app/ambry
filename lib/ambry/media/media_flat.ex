defmodule Ambry.Media.MediaFlat do
  @moduledoc """
  A flattened view of media.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Books.SeriesBookType
  alias Ambry.People.PersonName
  alias Ambry.Search.Query

  schema "media_flat" do
    field :book_id, :id
    field :title, :string
    field :part_number, :integer
    field :parts_total, :integer
    field :part_word, :string
    field :status, Ecto.Enum, values: [:pending, :processing, :error, :ready]
    field :missing_since, :utc_datetime
    field :full_cast, :boolean
    field :abridged, :boolean
    field :duration, :decimal
    field :chapters, :integer
    field :book, :string
    field :thumbnail, :string
    field :series, {:array, SeriesBookType.Type}
    field :universes, :string
    field :authors, {:array, PersonName.Type}
    field :narrators, {:array, PersonName.Type}
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]
    field :publisher, :string
    field :has_description, :boolean
    field :direct_play, :boolean

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    from m in query,
      where: m.book_id in subquery(Query.ids(search_string, :book))
  end

  def filter(query, :status, status), do: from(p in query, where: [status: ^status])
  def filter(query, :full_cast, full_cast?), do: from(p in query, where: [full_cast: ^full_cast?])
  def filter(query, :abridged, abridged?), do: from(p in query, where: [abridged: ^abridged?])

  def filter(query, :has_chapters, true), do: from(p in query, where: p.chapters > 0)
  def filter(query, :has_chapters, false), do: from(p in query, where: p.chapters == 0)

  def filter(query, :missing, true), do: from(p in query, where: not is_nil(p.missing_since))
  def filter(query, :missing, false), do: from(p in query, where: is_nil(p.missing_since))

  def filter(query, :direct_play, direct_play?),
    do: from(p in query, where: p.direct_play == ^direct_play?)
end
