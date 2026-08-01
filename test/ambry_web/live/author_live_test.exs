defmodule AmbryWeb.AuthorLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders an author page with authored books", %{conn: conn} do
    book =
      insert(:book,
        book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
      )

    %{book_authors: [%{author: author}]} = book

    {:ok, _view, html} = live(conn, ~p"/authors/#{author.id}")

    assert html =~ html_escape(author.name)
    assert html =~ html_escape(book.title)
  end

  test "renders an author page with no authored books", %{conn: conn} do
    %{author_people: [%{author: author}]} = insert(:person, authors: [build(:author)])

    {:ok, _view, html} = live(conn, ~p"/authors/#{author.id}")

    assert html =~ html_escape(author.name)
  end

  test "shows media the author translated", %{conn: conn} do
    author = insert(:author, name: "Ken Liu", person: build(:person))
    book = insert(:book, title: "The Three-Body Problem")

    insert(:media,
      book: book,
      status: :ready,
      title: "The Three-Body Problem (English)",
      media_translators: [build(:media_translator, author: author)]
    )

    {:ok, _view, html} = live(conn, ~p"/authors/#{author.id}")

    assert html =~ "Translated"
    assert html =~ html_escape("The Three-Body Problem (English)")
  end

  test "renders a narrator page with no narrated media", %{conn: conn} do
    narrator = insert(:narrator, person: build(:person))

    {:ok, _view, html} = live(conn, ~p"/narrators/#{narrator.id}")

    assert html =~ html_escape(narrator.name)
  end
end
