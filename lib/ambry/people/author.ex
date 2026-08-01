defmodule Ambry.People.Author do
  @moduledoc """
  An author writes books.

  Linked to one or more People, so one person can write as multiple authors
  (pen names), and one author name can be shared by multiple people (composite
  pen names like James S.A. Corey).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Media.MediaTranslator
  alias Ambry.People.AuthorPerson
  alias Ambry.People.BookAuthor

  schema "authors" do
    has_many :book_authors, BookAuthor
    has_many :books, through: [:book_authors, :book]
    has_many :author_people, AuthorPerson
    has_many :people, through: [:author_people, :person]
    has_many :media_translators, MediaTranslator
    has_many :translated_media, through: [:media_translators, :media]

    field :name, :string

    timestamps(type: :utc_datetime)
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
    |> foreign_key_constraint(:id,
      name: "media_translators_author_id_fkey",
      message:
        "This author is credited as a translator on one or more recordings. You must first remove those credits."
    )
  end
end
