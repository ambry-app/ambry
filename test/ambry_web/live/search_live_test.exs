defmodule AmbryWeb.SearchLiveTest do
  use AmbryWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders search results page when searching for a book", %{conn: conn} do
    %{title: book_title} = :book |> insert()

    {:ok, _view, html} = live(conn, ~p"/search/#{book_title}")

    assert html =~ html_escape(book_title)
  end

  test "hides a book whose only media are unlisted", %{conn: conn} do
    book = insert(:book)

    media =
      insert(:media, book: book, status: :ready, unlisted_at: DateTime.utc_now(:second))

    {:ok, _view, html} = live(conn, ~p"/search/#{book.title}")

    doc = Floki.parse_document!(html)
    assert Floki.find(doc, "a[href='/audiobooks/#{media.id}']") == []
    assert Floki.find(doc, "a[href='/books/#{book.id}']") == []
  end

  test "renders search results page when searching for a person", %{conn: conn} do
    %{name: person_name} = :person |> insert()

    {:ok, _view, html} = live(conn, ~p"/search/#{person_name}")

    assert html =~ html_escape(person_name)
  end

  test "renders search results page when searching for a series", %{conn: conn} do
    book =
      :book
      |> insert(series_books: [build(:series_book, series: build(:series))])

    %{series_books: [%{series: %{name: series_name}}]} = book

    {:ok, _view, html} = live(conn, ~p"/search/#{series_name}")

    assert html =~ html_escape(series_name)
  end
end
