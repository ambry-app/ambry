defmodule AmbryWeb.Components.BookTiles do
  @moduledoc """
  Renders a responsive tiled grid of book links.
  """

  use AmbryWeb, :component

  alias Ambry.Books.Book
  alias Ambry.Series.SeriesBook

  alias Surface.Components.LiveRedirect

  prop books, :list
  prop show_load_more, :boolean, default: false
  prop load_more, :event

  @impl Phoenix.LiveComponent
  def update(%{books: books} = assigns, socket) do
    books =
      case books do
        [] -> []
        [%Book{} | _] = books -> Enum.map(books, &{&1, nil})
        [%SeriesBook{} | _] = series_books -> Enum.map(series_books, &{&1.book, &1.book_number})
      end

    {:ok, assign(socket, Map.put(assigns, :books, books))}
  end
end
