defmodule Ambry.Authors.Author do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book

  schema "authors" do
    many_to_many :books, Book, join_through: "authors_books"

    field :name, :string
    field :description, :string
    field :image_path, :string

    timestamps()
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name, :description, :image_path])
    |> validate_required([:name])
  end
end
