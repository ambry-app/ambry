defmodule Ambry.Books.SeriesFlat do
  @moduledoc """
  A flattened view of series.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.People.PersonName

  schema "series_flat" do
    field :name, :string
    field :books, :integer
    field :authors, {:array, PersonName.Type}

    timestamps()
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from s in query,
      where:
        ilike(s.name, ^search_string) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE (elem).name ILIKE ? OR (elem).person_name ILIKE ?)",
            s.authors,
            ^search_string,
            ^search_string
          )
  end
end
