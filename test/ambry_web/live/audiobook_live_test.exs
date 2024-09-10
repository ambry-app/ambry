defmodule AmbryWeb.AudiobookLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders an audiobook show page with its book details", %{conn: conn} do
    %{id: media_id, book: %{title: book_title}} = insert(:media, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/audiobooks/#{media_id}")
    assert html =~ escape(book_title)
  end
end
