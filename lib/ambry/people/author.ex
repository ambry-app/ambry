defmodule Ambry.People.Author do
  @moduledoc """
  An author writes books.

  Linked to one or more People, so one person can write as multiple authors
  (pen names), and one author name can be shared by multiple people (composite
  pen names like James S.A. Corey).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.People.AuthorPerson
  alias Ambry.People.BookAuthor

  schema "authors" do
    has_many :book_authors, BookAuthor
    has_many :books, through: [:book_authors, :book]
    has_many :author_people, AuthorPerson
    has_many :people, through: [:author_people, :person]

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  An author created by the credit that names them, with the human behind them.

  One human is one `Person` holding identities, so a pen name invented on a
  book form cannot be a bare `authors` row: it arrives with an
  `authors_people` row and a person. The person is *named by the credit*
  unless the form said otherwise, because the operator typed one name into
  one box and being asked for it twice would be a question about our schema.

  A person who differs from their pen name — Robert Galbraith, J.K. Rowling —
  is said on the person's own card, which is where that question belongs.

  More than one human can stand behind one pen name (James S.A. Corey), so
  the list takes the sort and drop params every other editable list here does.
  """
  def credited_changeset(author, attrs) do
    attrs = Map.put_new_lazy(attrs, "author_people", fn -> [%{"person" => %{}}] end)

    author
    |> changeset(attrs)
    |> cast_assoc(:author_people,
      with: &AuthorPerson.credited_changeset(&1, &2, attrs["name"]),
      sort_param: :author_people_sort,
      drop_param: :author_people_drop
    )
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> foreign_key_constraint(:id,
      name: "authors_books_author_id_fkey",
      message:
        "This author is in use by one or more books. You must first remove them as an author from any associated books."
    )
  end
end
