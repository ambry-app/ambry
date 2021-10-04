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
  def changeset(series_book, %{"delete" => "true"}) do
    %{Ecto.Changeset.change(series_book, delete: true) | action: :delete}
  end

  def changeset(series_book, attrs) do
    series_book
    |> cast(attrs, [:book_id, :book_number, :series_id])
    |> validate_required([:book_number])
    |> validate_number(:book_number, greater_than: 0)
  end

  def series_assoc_changeset(series_book, attrs) do
    series_book
    |> changeset(attrs)
    |> validate_required([:book_id])
  end

  def book_assoc_changeset(series_book, attrs) do
    series_book
    |> changeset(attrs)
    |> validate_required([:series_id])
  end
end
