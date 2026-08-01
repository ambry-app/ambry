defmodule Ambry.Books.Universe do
  @moduledoc """
  A shared universe that books belong to (e.g. Cosmere, Revelation Space).

  Unlike series, universe membership is unnumbered; series appear within a
  universe through their books.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.BookUniverse

  schema "universes" do
    has_many :book_universes, BookUniverse, on_replace: :delete
    has_many :books, through: [:book_universes, :book]

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(universe, attrs) do
    universe
    |> cast(attrs, [:name])
    |> cast_assoc(:book_universes,
      with: &BookUniverse.universe_assoc_changeset/2,
      sort_param: :book_universes_sort,
      drop_param: :book_universes_drop
    )
    |> validate_required([:name])
  end
end
