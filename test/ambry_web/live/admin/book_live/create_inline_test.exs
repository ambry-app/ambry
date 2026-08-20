defmodule AmbryWeb.Admin.BookLive.CreateInlineTest do
  @moduledoc """
  Naming a record the library doesn't have, from the picker that credits it.

  The edit forms could only ever attach something that already existed, so
  crediting an author who was new meant leaving the form, making them by
  hand, and coming back — the asymmetry `EDIT_PARITY_PLAN.md` is about. The
  picker has always been able to offer "Create …"; these forms had it off.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Books
  alias Ambry.Books.Series
  alias Ambry.Books.Universe
  alias Ambry.People.Person
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  describe "a book's authors" do
    test "a typed name that matches nobody becomes a person on save", %{conn: conn} do
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{"new" => %{"author_id" => "", "author_name" => "Ursula K. Le Guin"}}
        }
      })

      assert [%Person{name: "Ursula K. Le Guin"} = person] = Repo.all(Person)
      assert [%{name: "Ursula K. Le Guin"}] = book.id |> Books.get_book!() |> Map.fetch!(:authors)

      # one human, one record: they hold the author identity rather than
      # being a second row of the same name
      assert [%{name: "Ursula K. Le Guin"}] =
               person |> Repo.preload(:authors) |> Map.fetch!(:authors)
    end

    # The half no param test can see: the box has to *offer* it. This is the
    # `text_name` the edit forms never passed, so the picker rendered as a
    # pure picker and there was no way to say "make one".
    test "the picker offers to create what it cannot find", %{conn: conn} do
      insert(:author, name: "Brandon Sanderson")
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_change(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{"new" => %{"author_id" => "", "author_name" => ""}}
        }
      })

      html =
        view
        |> element("#book_book_authors_0_author_id-input")
        |> render_change(%{"resolver" => %{"book_book_authors_0_author_id" => "Le Gu"}})

      assert html =~ "Create “Le Gu”"
    end

    test "a name the library already knows credits the person it has", %{conn: conn} do
      person = insert(:person, name: "Ursula K. Le Guin")
      author = insert(:author, name: "Ursula K. Le Guin", person: person)
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{"new" => %{"author_id" => "", "author_name" => "Ursula K. Le Guin"}}
        }
      })

      assert [only] = Repo.all(Person)
      assert only.id == person.id
      assert [credited] = book.id |> Books.get_book!() |> Map.fetch!(:authors)
      assert credited.id == author.id
    end

    # Nothing is created while the form is being filled in: a name typed and
    # then thought better of leaves no trace.
    test "nothing is created until the form is saved", %{conn: conn} do
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_change(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{"new" => %{"author_id" => "", "author_name" => "Ursula K. Le Guin"}}
        }
      })

      assert Repo.all(Person) == []
    end

    # The row is answerable either way, so a picker holding a name rather than
    # an id is not an unfinished row.
    test "a named row does not read as blank", %{conn: conn} do
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      html =
        view
        |> form("#book-form")
        |> render_change(%{
          "book" => %{
            "book_authors_sort" => ["new"],
            "book_authors" => %{
              "new" => %{"author_id" => "", "author_name" => "Ursula K. Le Guin"}
            }
          }
        })

      refute html =~ "can&#39;t be blank"
    end
  end

  describe "a book's series and universes" do
    test "typed names become a series and a universe on save", %{conn: conn} do
      book = insert(:book, series_books: [], book_universes: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "series_books_sort" => ["new"],
          "series_books" => %{
            "new" => %{"series_id" => "", "series_name" => "Earthsea", "book_number" => "1"}
          },
          "book_universes_sort" => ["new"],
          "book_universes" => %{
            "new" => %{"universe_id" => "", "universe_name" => "Hainish"}
          }
        }
      })

      assert [%Series{name: "Earthsea"}] = Repo.all(Series)
      assert [%Universe{name: "Hainish"}] = Repo.all(Universe)

      book = book.id |> Books.get_book!() |> Repo.preload([:series, :universes])
      assert [%{name: "Earthsea"}] = book.series
      assert [%{name: "Hainish"}] = book.universes
    end
  end

  describe "an audiobook's narrators" do
    test "a typed name that matches nobody becomes a person on save", %{conn: conn} do
      media = insert(:media, book: insert(:book), media_narrators: [])

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "media_narrators_sort" => ["new"],
          "media_narrators" => %{
            "new" => %{"narrator_id" => "", "narrator_name" => "Kate Reading"}
          }
        }
      })

      assert [%Person{name: "Kate Reading"}] = Repo.all(Person)

      assert [%{name: "Kate Reading"}] =
               media.id
               |> Ambry.Media.get_media!()
               |> Repo.preload(:narrators)
               |> Map.fetch!(:narrators)
    end
  end
end
