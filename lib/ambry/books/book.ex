defmodule Ambry.Books.Book do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Authors.{Author, BookAuthor}
  alias Ambry.Series.Series
  alias Ambry.Media.Media
  alias Ambry.Series.SeriesBook

  schema "books" do
    has_many :media, Media
    has_many :series_books, SeriesBook
    has_many :book_authors, BookAuthor

    many_to_many :series, Series, join_through: "books_series"
    many_to_many :authors, Author, join_through: "authors_books"

    field :title, :string
    field :published, :date
    field :description, :string
    field :image_path, :string

    timestamps()
  end

  @doc false
  def changeset(book, attrs) do
    book
    |> cast(attrs, [:title, :published, :description, :image_path])
    |> cast_assoc(:series_books)
    |> cast_assoc(:book_authors)
    |> validate_required([:title, :published])
  end
end
