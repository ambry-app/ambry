defmodule Ambry.Books.BookFlat do
  @moduledoc """
  A flattened view of books.
  """

  use Ecto.Schema

  alias Ambry.Ecto.Types.PersonName

  schema "books_flat" do
    field :title, :string
    field :published, :date
    field :image_path, :string
    field :authors, {:array, PersonName}
    field :series, {:array, :string}
    field :universe, :string

    timestamps()
  end
end
