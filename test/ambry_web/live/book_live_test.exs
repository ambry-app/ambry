defmodule AmbryWeb.BookLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a book show page with its media", %{conn: conn} do
    %{book: %{id: book_id, title: book_title}} = insert(:media, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/books/#{book_id}")
    assert html =~ escape(book_title)
  end
end
