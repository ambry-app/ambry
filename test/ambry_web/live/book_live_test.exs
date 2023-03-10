defmodule AmbryWeb.BookLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a book show page", %{conn: conn} do
    %{id: book_id, title: book_title} = insert(:book)

    {:ok, _view, html} = live(conn, ~p"/books/#{book_id}")
    assert html =~ escape(book_title)
  end
end
