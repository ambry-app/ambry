defmodule Ambry.People.PersonFlat do
  @moduledoc """
  A flattened view of people.
  """

  use Ambry.FlatSchema

  schema "people_flat" do
    field :name, :string
    field :image_path, :string

    field :is_author, :boolean
    field :writing_as, {:array, :string}
    field :authored_books, :integer

    field :is_narrator, :boolean
    field :narrating_as, {:array, :string}
    field :narrated_media, :integer

    timestamps()
  end

  def filter(query, :search, search_string) do
    search_string = "%#{search_string}%"

    from p in query,
      where:
        ilike(p.name, ^search_string) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE elem ILIKE ?)",
            p.writing_as,
            ^search_string
          ) or
          fragment(
            "EXISTS (SELECT FROM unnest(?) elem WHERE elem ILIKE ?)",
            p.narrating_as,
            ^search_string
          )
  end

  def filter(query, :is_author, is_author?), do: from(p in query, where: [is_author: ^is_author?])

  def filter(query, :is_narrator, is_narrator?), do: from(p in query, where: [is_narrator: ^is_narrator?])
end
