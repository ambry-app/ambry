defmodule AmbryWeb.LibraryLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the library", %{conn: conn} do
    %{book: %{title: book_title}} = insert(:media, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/library")
    assert html =~ escape(book_title)
  end
end
