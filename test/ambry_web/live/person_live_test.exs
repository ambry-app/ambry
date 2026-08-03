defmodule AmbryWeb.PersonLiveTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders a person show page with authored books", %{conn: conn} do
    book =
      insert(:book,
        book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
      )

    %{book_authors: [%{author: %{author_people: [%{person: person}]}}]} = book
    insert(:media, book: book, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/people/#{person.id}")

    assert html =~ html_escape(person.name)
    assert html =~ html_escape(book.title)
  end

  test "a composite pen name's section credits the co-writers", %{conn: conn} do
    abraham = insert(:person, name: "Daniel Abraham")
    franck = insert(:person, name: "Ty Franck")
    author = insert(:author, name: "James S.A. Corey", people: [abraham, franck])
    book = insert(:book, book_authors: [build(:book_author, author: author)])
    insert(:media, book: book, status: :ready)

    {:ok, _view, html} = live(conn, ~p"/people/#{franck.id}")

    text = html |> Floki.parse_document!() |> Floki.text() |> String.replace(~r/\s+/, " ")
    assert text =~ "Written by Ty Franck with Daniel Abraham as James S.A. Corey"
  end

  test "renders a person show page with narrated books", %{conn: conn} do
    media =
      insert(:media,
        book: build(:book),
        status: :ready,
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
