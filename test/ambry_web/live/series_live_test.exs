defmodule AmbryWeb.SeriesLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a series show page", %{conn: conn} do
    series = insert(:series)
    book = insert(:book, series_books: [%{series: series, book_number: 1}])

    {:ok, _view, html} = live(conn, ~p"/series/#{series.id}")

    assert html =~ series.name
    assert html =~ String.replace(book.title, "'", "&#39;")
  end
end
