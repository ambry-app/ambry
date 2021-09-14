defmodule Ambry.Series.Series do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  schema "series" do
    has_many :series_books, SeriesBook

    many_to_many :books, Book, join_through: "books_series"

    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(series, attrs) do
    series
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
