defmodule AmbryWeb.SearchLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders search results page when searching for a book", %{conn: conn} do
    %{title: book_title} = :book |> insert() |> with_search_index()

    {:ok, _view, html} = live(conn, ~p"/search/#{book_title}")

    assert html =~ html_escape(book_title)
  end

  test "renders search results page when searching for a person", %{conn: conn} do
    %{name: person_name} = :person |> insert() |> with_search_index()

    {:ok, _view, html} = live(conn, ~p"/search/#{person_name}")

    assert html =~ html_escape(person_name)
  end

  test "renders search results page when searching for a series", %{conn: conn} do
    book =
      :book
      |> insert(series_books: [build(:series_book, series: build(:series))])
      |> with_search_index()

    %{series_books: [%{series: %{name: series_name}}]} = book

    {:ok, _view, html} = live(conn, ~p"/search/#{series_name}")

    assert html =~ html_escape(series_name)
  end
end
