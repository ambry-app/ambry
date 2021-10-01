defmodule Ambry.Authors.Author do
  @moduledoc """
  An author writes books.

  Belongs to a Person, so one person can write as multiple authors (pen names).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.People.Person

  schema "authors" do
    many_to_many :books, Book, join_through: "authors_books"
    belongs_to :person, Person

    field :name, :string
    field :delete, :boolean, virtual: true

    timestamps()
  end

  @doc false
  def changeset(author, %{"delete" => "true"}) do
    %{Ecto.Changeset.change(author, delete: true) | action: :delete}
  end

  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
