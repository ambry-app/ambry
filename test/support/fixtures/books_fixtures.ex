defmodule Ambry.BooksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ambry.Books` context.
  """

  @seconds_per_year 31_536_000

  def unique_book_title, do: "Book #{System.unique_integer()}"

  def valid_book_published,
    do:
      (("Etc/UTC" |> DateTime.now!() |> DateTime.to_unix()) -
         Enum.random(0..(40 * @seconds_per_year)))
      |> DateTime.from_unix!()
      |> DateTime.to_date()

  def valid_book_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: unique_book_title(),
      published: valid_book_published()
    })
  end

  def book_fixture(attrs \\ %{}) do
    {:ok, book} =
      attrs
      |> valid_book_attributes()
      |> Ambry.Books.create_book()

    book
  end
end
