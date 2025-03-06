defmodule Ambry.Books.Book do
  @moduledoc """
  A book.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.SeriesBook
  alias Ambry.Media.Media
  alias Ambry.People.BookAuthor

  schema "books" do
    has_many :media, Media, preload_order: [desc: :published]
    has_many :series_books, SeriesBook, on_replace: :delete
    has_many :book_authors, BookAuthor, on_replace: :delete
    has_many :series, through: [:series_books, :series]
    has_many :authors, through: [:book_authors, :author]

    field :title, :string
    field :published, :date
    field :published_format, Ecto.Enum, values: [:full, :year_month, :year]

    # deprecated
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(book, attrs) do
    book
    |> cast(attrs, [:title, :published, :published_format, :description])
    |> cast_assoc(:series_books,
      with: &SeriesBook.book_assoc_changeset/2,
      sort_param: :series_books_sort,
      drop_param: :series_books_drop
    )
    |> cast_assoc(:book_authors,
      sort_param: :book_authors_sort,
      drop_param: :book_authors_drop
    )
    |> validate_required([:title, :published])
    |> foreign_key_constraint(:media, name: "media_book_id_fkey")
  end
end
