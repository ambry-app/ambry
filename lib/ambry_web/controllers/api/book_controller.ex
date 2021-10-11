defmodule AmbryWeb.API.BookController do
  use AmbryWeb, :controller

  alias Ambry.Books

  action_fallback AmbryWeb.FallbackController

  @limit 10

  def index(conn, params) do
    page =
      case params |> Map.get("page", "1") |> Integer.parse() do
        {page, _} when page >= 1 -> page
        {_bad_page, _} -> 1
        :error -> 1
      end

    offset = page_to_offset(page)

    books = Books.get_recent_books!(offset, @limit)
    render(conn, "index.json", books: books)
  end

  def show(conn, %{"id" => id}) do
    book = Books.get_book_with_media!(id)
    render(conn, "show.json", book: book)
  end

  defp page_to_offset(page) do
    page * @limit - @limit
  end
end
