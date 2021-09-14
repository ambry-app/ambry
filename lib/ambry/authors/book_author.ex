defmodule Ambry.Authors.BookAuthor do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Authors.Author

  schema "authors_books" do
    belongs_to :author, Author
    belongs_to :book, Book
  end

  @doc false
  def changeset(book_author, attrs) do
    book_author
    |> cast(attrs, [:author_id])
    |> cast_assoc(:author)
    |> validate_author()
  end

  defp validate_author(changeset) do
    if get_field(changeset, :author) do
      changeset
    else
      validate_required(changeset, :author_id)
    end
  end
end
