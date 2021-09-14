defmodule Ambry.Series.SeriesBook do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Series.Series

  schema "books_series" do
    belongs_to :book, Book
    belongs_to :series, Series

    field :book_number, :decimal
  end

  @doc false
  def changeset(series_book, attrs) do
    series_book
    |> cast(attrs, [:book_number, :series_id])
    |> cast_assoc(:series)
    |> validate_required([:book_number])
    |> validate_number(:book_number, greater_than: 0)
    |> validate_series()
  end

  defp validate_series(changeset) do
    if get_field(changeset, :series) do
      changeset
    else
      validate_required(changeset, :series_id)
    end
  end
end
