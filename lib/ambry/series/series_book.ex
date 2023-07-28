defmodule Ambry.Series.SeriesBook do
  @moduledoc """
  Join table between books and series.

  Also stores the book number (e.g. which number book is this in the series).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Books.Book
  alias Ambry.Series.Series

  schema "books_series" do
    belongs_to :book, Book
    belongs_to :series, Series

    field :book_number, :decimal
    field :delete, :boolean, virtual: true
  end

  @doc false
  def changeset(series_book, attrs) do
    series_book
    |> cast(attrs, [:book_id, :book_number, :series_id, :delete])
    |> validate_required([:book_number])
    |> validate_number(:book_number, greater_than_or_equal_to: 0)
    |> maybe_apply_delete()
  end

  defp maybe_apply_delete(changeset) do
    if Ecto.Changeset.get_change(changeset, :delete, false) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end

  def series_assoc_changeset(series_book, attrs) do
    series_book
    |> changeset(attrs)
    |> validate_required([:book_id])
    |> unique_constraint(:book_id, name: "books_series_book_id_series_id_index")
  end

  def book_assoc_changeset(series_book, attrs) do
    series_book
    |> changeset(attrs)
    |> cast_assoc(:series)
    |> validate_required([:series_id])
    |> unique_constraint(:series_id, name: "books_series_book_id_series_id_index")
  end
end
