defmodule AmbryWeb.PersonLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a person show page with authored books", %{conn: conn} do
    book =
      insert(:book,
        book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
      )

    %{book_authors: [%{author: %{person: person}}]} = book

    {:ok, _view, html} = live(conn, ~p"/people/#{person.id}")

    assert html =~ html_escape(person.name)
    assert html =~ html_escape(book.title)
  end

  test "renders a person show page with narrated books", %{conn: conn} do
    media =
      insert(:media,
        book: build(:book),
        media_narrators: [
          build(:media_narrator, narrator: build(:narrator, person: build(:person)))
        ]
      )

    %{book: book, media_narrators: [%{narrator: %{person: person}}]} = media

    {:ok, _view, html} = live(conn, ~p"/people/#{person.id}")

    assert html =~ html_escape(person.name)
    assert html =~ html_escape(book.title)
  end
end
