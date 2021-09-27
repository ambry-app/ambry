defmodule Ambry.Authors.BookAuthor do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Authors.Author

  schema "authors_books" do
    belongs_to :author, Author
    belongs_to :book, Book

    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(book_author, %{"delete" => "true"}) do
    %{Ecto.Changeset.change(book_author, delete: true) | action: :delete}
  end

  def changeset(book_author, attrs) do
    book_author
    |> cast(attrs, [:author_id])
    |> cast_assoc(:author)
    |> validate_required(:author_id)
  end
end
