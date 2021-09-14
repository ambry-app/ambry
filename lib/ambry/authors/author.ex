defmodule Ambry.Authors.Author do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.People.Person

  schema "authors" do
    many_to_many :books, Book, join_through: "authors_books"
    belongs_to :person, Person

    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name, :description, :image_path])
    |> validate_required([:name])
  end
end
