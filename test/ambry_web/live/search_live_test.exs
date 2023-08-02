defmodule AmbryWeb.SearchLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders search results page when searching for a book", %{conn: conn} do
    %{title: book_title} = book = insert(:book)
    insert_index!(book)

    {:ok, _view, html} = live(conn, ~p"/search/#{book_title}")

    assert html =~ escape(book_title)
  end

  test "renders search results page when searching for a person", %{conn: conn} do
    %{name: person_name} = person = insert(:person)
    insert_index!(person)

    {:ok, _view, html} = live(conn, ~p"/search/#{person_name}")

    assert html =~ escape(person_name)
  end

  test "renders search results page when searching for a series", %{conn: conn} do
    %{series_books: [%{series: %{name: series_name} = series} | _rest]} = insert(:book)
    insert_index!(series)

    {:ok, _view, html} = live(conn, ~p"/search/#{series_name}")

    assert html =~ escape(series_name)
  end
end
