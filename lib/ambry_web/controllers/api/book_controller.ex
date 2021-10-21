defmodule AmbryWeb.API.BookController do
  use AmbryWeb, :controller

  import AmbryWeb.API.ControllerUtils

  alias Ambry.Books

  action_fallback AmbryWeb.FallbackController

  @limit 10

  def index(conn, params) do
    offset = offset_from_params(params, @limit)

    books = Books.get_recent_books!(offset, @limit)
    render(conn, "index.json", books: books)
  end

  def show(conn, %{"id" => id}) do
    book = Books.get_book_with_media!(id)
    render(conn, "show.json", book: book)
  end
end
