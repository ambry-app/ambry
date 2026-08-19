defmodule Ambry.People.PersonFlat do
  @moduledoc """
  A flattened view of people.
  """

  use Ambry.Repo.FlatSchema

  alias Ambry.Search.Query

  schema "people_flat" do
    field :name, :string
    field :thumbnail, :string
    field :has_description, :boolean

    field :is_author, :boolean
    field :writing_as, {:array, :string}
    field :authored_books, :integer

    field :is_narrator, :boolean
    field :narrating_as, {:array, :string}
    field :narrated_media, :integer

    timestamps(type: :utc_datetime)
  end

  def filter(query, :search, search_string) do
    from p in query,
      where: p.id in subquery(Query.ids(search_string, :person))
  end

  def filter(query, :is_author, is_author?), do: from(p in query, where: [is_author: ^is_author?])

  def filter(query, :is_narrator, is_narrator?),
    do: from(p in query, where: [is_narrator: ^is_narrator?])
end
