defmodule AmbryWeb.Components.BookTiles do
  @moduledoc """
  Renders a responsive tiled grid of book links.
  """

  use AmbryWeb, :component

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias AmbryWeb.Endpoint

  alias Surface.Components.LiveRedirect

  prop books, :list
  prop show_load_more, :boolean, default: false
  prop load_more, :event

  defp books_with_numbers(books_assign) do
    case books_assign do
      [] -> []
      [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
      [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
    end
  end
end
