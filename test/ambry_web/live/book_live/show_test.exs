defmodule AmbryWeb.BookLive.ShowTest do
  use AmbryWeb.ConnCase

  setup :register_and_log_in_user

  test "renders a book show page", %{conn: conn} do
    %{id: book_id, title: book_title} = insert(:book)

    {:ok, _view, html} = live(conn, "/books/#{book_id}")
    assert html =~ escape(book_title)
  end
end
