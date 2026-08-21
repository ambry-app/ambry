defmodule Ambry.People.BookAuthor do
  @moduledoc """
  Join table for authors to books.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Ecto.EntityRef
  alias Ambry.People.Author

  schema "authors_books" do
    belongs_to :author, Author
    belongs_to :book, Book

    # Which credit comes first. The first one is the book's primary author —
    # what the library naming template uses for the folder, and the order
    # every list of authors is rendered in.
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(book_author, attrs) do
    book_author
    |> cast(attrs, [:author_id, :position])
    |> EntityRef.cast_new(:author, :author_id, with: &Author.credited_changeset/2)
    |> EntityRef.validate_linked_or_new(:author_id, :author)
    |> unique_constraint([:author_id, :book_id])
  end
end
