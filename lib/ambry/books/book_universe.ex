defmodule Ambry.Books.BookUniverse do
  @moduledoc """
  Join table between books and universes. Membership is unnumbered.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Books.Universe
  alias Ambry.Ecto.EntityRef

  schema "books_universes" do
    belongs_to :book, Book
    belongs_to :universe, Universe

    timestamps(type: :utc_datetime)
  end

  @doc false
  # Either points at a universe or brings a new one — `Ambry.Ecto.EntityRef`.
  def book_assoc_changeset(book_universe, attrs) do
    book_universe
    |> cast(attrs, [:universe_id])
    |> EntityRef.cast_new(:universe, :universe_id)
    |> EntityRef.validate_linked_or_new(:universe_id, :universe)
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
