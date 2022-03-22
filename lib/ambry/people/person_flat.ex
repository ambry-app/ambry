defmodule Ambry.People.PersonFlat do
  @moduledoc """
  A flattened view of people.
  """

  use Ecto.Schema

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
end
