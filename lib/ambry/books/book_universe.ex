defmodule Ambry.Books.BookUniverse do
  @moduledoc """
  Join table between books and universes. Membership is unnumbered.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Books.Universe

  schema "books_universes" do
    belongs_to :book, Book
    belongs_to :universe, Universe

    # The name typed into the picker when it named a universe the library
    # doesn't have. Resolved when the form is saved — `Ambry.Ecto.EntityRef`.
    field :universe_name, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def book_assoc_changeset(book_universe, attrs) do
    book_universe
    |> cast(attrs, [:universe_id, :universe_name])
    |> Ambry.Ecto.EntityRef.validate_linked_or_named(:universe_id, :universe_name)
    |> unique_constraint([:book_id, :universe_id])
  end

  @doc false
  def universe_assoc_changeset(book_universe, attrs) do
    book_universe
    |> cast(attrs, [:book_id])
    |> validate_required(:book_id)
    |> unique_constraint([:book_id, :universe_id])
  end
end
