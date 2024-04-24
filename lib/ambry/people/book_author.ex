defmodule Ambry.People.BookAuthor do
  @moduledoc """
  Join table for authors to books.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.People.Author

  schema "authors_books" do
    belongs_to :author, Author
    belongs_to :book, Book
  end

  @doc false
  def changeset(book_author, attrs) do
    book_author
    |> cast(attrs, [:author_id])
    |> validate_required(:author_id)
    |> unique_constraint([:author_id, :book_id])
  end
end
