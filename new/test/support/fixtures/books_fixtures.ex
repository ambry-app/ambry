defmodule Ambry.BooksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ambry.Books` context.
  """

  @doc """
  Generate a book.
  """
  def book_fixture(attrs \\ %{}) do
    {:ok, book} =
      attrs
      |> Enum.into(%{
        title: "some title"
      })
      |> Ambry.Books.create_book()

    book
  end
end
