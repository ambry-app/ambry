defmodule AmbryWeb.Preview.BookController do
  use AmbryWeb, :controller

  alias Ambry.Books

  def show(conn, %{"id" => book_id}) do
    book = Books.get_book_with_media!(book_id)

    conn
    |> put_session(:user_return_to, current_path(conn))
    |> render(:show, %{
      book: book,
      page_title: Books.get_book_description(book),
      og: %{
        title: Books.get_book_description(book),
        image: unverified_url(conn, book.image_path),
        description: truncate_markdown(book.description),
        url: url(conn, ~p"/books/#{book.id}")
      }
    })
  end

  defp truncate_markdown(markdown) do
    (markdown
     |> Earmark.as_html!()
     |> Floki.parse_document!()
     |> Floki.text()
     |> String.slice(0..252)) <>
      "..."
  end
end
