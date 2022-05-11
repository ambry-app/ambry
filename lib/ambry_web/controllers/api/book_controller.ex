defmodule AmbryWeb.API.BookController do
  use AmbryWeb, :controller

  import AmbryWeb.API.ControllerUtils

  alias Ambry.Books

  action_fallback AmbryWeb.FallbackController

  @limit 25

  def index(conn, params) do
    offset = offset_from_params(params, @limit)

    {books, has_more?} = Books.get_recent_books(offset, @limit)
    render(conn, "index.json", books: books, has_more?: has_more?)
  end

  def show(conn, %{"id" => id}) do
    book = Books.get_book_with_media!(id)
    render(conn, "show.json", book: book)
  end
end
