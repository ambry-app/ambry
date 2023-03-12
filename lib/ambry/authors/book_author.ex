defmodule Ambry.Authors.BookAuthor do
  @moduledoc """
  Join table for authors to books.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Authors.Author
  alias Ambry.Books.Book

  schema "authors_books" do
    belongs_to :author, Author
    belongs_to :book, Book

    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(book_author, attrs) do
    book_author
    |> cast(attrs, [:author_id, :delete])
    |> validate_required(:author_id)
    |> maybe_apply_delete()
    |> unique_constraint([:author_id, :book_id])
  end

  defp maybe_apply_delete(changeset) do
    if Ecto.Changeset.get_change(changeset, :delete, false) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
