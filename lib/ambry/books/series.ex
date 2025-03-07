defmodule Ambry.Books.Series do
  @moduledoc """
  A series of books.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.SeriesBook

  schema "series" do
    has_many :series_books, SeriesBook, preload_order: [asc: :book_number], on_replace: :delete
    has_many :books, through: [:series_books, :book]
    has_many :authors, through: [:books, :authors]

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(series, attrs) do
    series
    |> cast(attrs, [:name])
    |> cast_assoc(:series_books,
      with: &SeriesBook.series_assoc_changeset/2,
      sort_param: :series_books_sort,
      drop_param: :series_books_drop
    )
    |> validate_required([:name])
  end
end
