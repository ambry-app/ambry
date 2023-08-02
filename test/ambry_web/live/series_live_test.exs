defmodule AmbryWeb.SeriesLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a series show page", %{conn: conn} do
    %{series_books: [%{series: %{id: series_id, name: series_name}} | _rest]} = insert(:book)

    {:ok, _view, html} = live(conn, ~p"/series/#{series_id}")
    assert html =~ escape(series_name)
  end
end
