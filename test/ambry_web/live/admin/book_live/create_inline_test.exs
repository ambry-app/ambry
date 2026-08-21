defmodule AmbryWeb.Admin.BookLive.CreateInlineTest do
  @moduledoc """
  Naming a record the library doesn't have, from the picker that credits it.

  The edit forms could only ever attach something that already existed, so
  crediting an author who was new meant leaving the form, making them by
  hand, and coming back — the asymmetry `EDIT_PARITY_PLAN.md` is about. The
  picker has always been able to offer "Create …"; these forms had it off.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Books
  alias Ambry.Books.Series
  alias Ambry.Books.Universe
  alias Ambry.People.Person
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  defp patch_search do
    record = %Ambry.Metadata.Provider.Book{
      provider: "rreading_glasses",
      id: "76027608",
      title: "Dungeon Crawler Carl",
      authors: [
        %Ambry.Metadata.Provider.Contributor{id: "1", name: "Matt Dinniman", role: "author"}
      ],
      series: [
        %Ambry.Metadata.Provider.Series{id: "2", name: "Dungeon Crawler Carl", number: "1"}
      ]
    }

    patch(Ambry.Metadata.Providers, :search_books, fn
      "rreading_glasses", _query, _opts -> {:ok, [record]}
      _other, _query, _opts -> {:ok, []}
    end)
  end

  defp search(view, fields) do
    view |> form("#research-work", fields) |> render_submit()
    render_async(view)
  end

  defp tick_first_record(view) do
    view |> element(~s{[data-role="record"] input[type="checkbox"]}) |> render_click()
  end

  describe "a book's authors" do
    test "a typed name that matches nobody becomes a person on save", %{conn: conn} do
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{"author_id" => "", "author" => %{"name" => "Ursula K. Le Guin"}}
          }
        }
      })

      assert [%Person{name: "Ursula K. Le Guin"} = person] = Repo.all(Person)
      assert [%{name: "Ursula K. Le Guin"}] = book.id |> Books.get_book!() |> Map.fetch!(:authors)

      # one human, one record: they hold the author identity rather than
      # being a second row of the same name
      assert [%{name: "Ursula K. Le Guin"}] =
               person |> Repo.preload(:authors) |> Map.fetch!(:authors)
    end

    # A form posts an unpicked field as "", which is perfectly truthy, so the
    # box wore the "existing" badge over a name the library had never seen —
    # the one thing that badge exists to tell you.
    test "a typed name is badged new, not existing", %{conn: conn} do
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      html =
        view
        |> form("#book-form")
        |> render_change(%{
          "book" => %{
            "book_authors_sort" => ["new"],
            "book_authors" => %{
              "new" => %{"author_id" => "", "author" => %{"name" => "Zephyr Quillfeather"}}
            }
          }
        })

      badge =
        html
        |> Floki.parse_document!()
        |> Floki.find("#book_book_authors_0_author_id span.pointer-events-none")
        |> Floki.text()
        |> String.trim()

      assert badge == "new"
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
          "book_authors" => %{"new" => %{"author_id" => "", "author" => %{"name" => ""}}}
        }
      })

      html =
        view
        |> element("#book_book_authors_0_author_id-input")
        |> render_change(%{"resolver" => %{"book_book_authors_0_author_id" => "Le Gu"}})

      assert html =~ "Create “Le Gu”"
    end

    # Picking is how you credit somebody the library has: the box searched as
    # the name was typed and listed them. **Create means create** — an
    # explicit choice made with the match on screen — so this is the one thing
    # the old by-name resolution did that nesting does not, and the picker's
    # own list is what stands in its place.
    test "picking the person the library has credits them, with no second record", %{conn: conn} do
      person = insert(:person, name: "Ursula K. Le Guin")
      author = insert(:author, name: "Ursula K. Le Guin", person: person)
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => to_string(author.id),
              "author" => %{"name" => "Ursula K. Le Guin"}
            }
          }
        }
      })

      # the nested name the picker leaves behind is ignored on a linked row —
      # that record is shared, and a form that cast it could rewrite it
      assert [only] = Repo.all(Person)
      assert only.id == person.id
      assert [credited] = book.id |> Books.get_book!() |> Map.fetch!(:authors)
      assert credited.id == author.id
      assert Repo.get!(Ambry.People.Author, author.id).name == "Ursula K. Le Guin"
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
          "book_authors" => %{
            "new" => %{"author_id" => "", "author" => %{"name" => "Ursula K. Le Guin"}}
          }
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
              "new" => %{"author_id" => "", "author" => %{"name" => "Ursula K. Le Guin"}}
            }
          }
        })

      refute html =~ "can&#39;t be blank"
    end
  end

  # The rule this whole arc has to keep: **an edit form does nothing until
  # Save.** The import form saves on every change because nothing it holds is
  # real yet; an edit form is a record that already exists, and a control that
  # wrote on click left records behind on every book the operator opened,
  # looked at and abandoned.
  describe "nothing is written before Save" do
    test "a proposal chip stages the author rather than creating them", %{conn: conn} do
      patch_search()
      book = insert(:book, title: "Dungeon Crawler Carl", book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
      search(view, %{"title" => "Dungeon Crawler Carl"})
      tick_first_record(view)

      before = Repo.aggregate(Person, :count)
      html = view |> element(~s{#proposals-authors button}) |> render_click()

      # the row is there, holding a name
      assert html =~ "Matt Dinniman"
      assert Repo.aggregate(Person, :count) == before
      refute Repo.get_by(Person, name: "Matt Dinniman")
      # and the chip reports it, so a second click can't stage it twice
      refute has_element?(view, ~s{#proposals-authors button})

      view |> form("#book-form") |> render_submit()

      assert %Person{} = Repo.get_by(Person, name: "Matt Dinniman")
    end

    test "a proposed series is staged too", %{conn: conn} do
      patch_search()
      book = insert(:book, title: "Dungeon Crawler Carl", series_books: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
      search(view, %{"title" => "Dungeon Crawler Carl"})
      tick_first_record(view)

      view |> element(~s{#proposals-series button}) |> render_click()
      refute Repo.get_by(Series, name: "Dungeon Crawler Carl")

      view |> form("#book-form") |> render_submit()
      assert %Series{} = Repo.get_by(Series, name: "Dungeon Crawler Carl")
    end
  end

  # One human is one `Person` holding identities, and this is where that is
  # easiest to break: the library knows Ty Franck, and a book credits him as
  # half of James S.A. Corey. A second person row of that name would be the
  # duplicate the model exists to prevent.
  describe "a person the library already has" do
    test "gains the identity rather than a second record of themselves", %{conn: conn} do
      person = insert(:person, name: "Ty Franck", narrators: [])
      book = insert(:book, book_authors: [])

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      # what a chip stages when the human is known but the credit is not
      view
      |> form("#book-form")
      |> render_submit(%{
        "book" => %{
          "book_authors_sort" => ["new"],
          "book_authors" => %{
            "new" => %{
              "author_id" => "",
              "author" => %{
                "name" => "James S.A. Corey",
                "author_people" => %{"0" => %{"person_id" => to_string(person.id)}}
              }
            }
          }
        }
      })

      # one Ty Franck, holding a second identity
      assert [only] = Repo.all(from p in Person, where: p.name == "Ty Franck")
      assert only.id == person.id

      assert [%{name: "James S.A. Corey"}] =
               Person |> Repo.get!(person.id) |> Repo.preload(:authors) |> Map.fetch!(:authors)

      assert [%{name: "James S.A. Corey"}] =
               book.id |> Books.get_book!() |> Map.fetch!(:authors)
    end

    test "an audiobook credits them as a narrator the same way", %{conn: conn} do
      person = insert(:person, name: "Ty Franck", narrators: [])
      media = insert(:media, book: insert(:book), media_narrators: [])

      {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

      view
      |> form("#media-form")
      |> render_submit(%{
        "media" => %{
          "media_narrators_sort" => ["new"],
          "media_narrators" => %{
            "new" => %{
              "narrator_id" => "",
              "narrator" => %{"name" => "Ty Franck", "person_id" => to_string(person.id)}
            }
          }
        }
      })

      assert [only] = Repo.all(from p in Person, where: p.name == "Ty Franck")
      assert only.id == person.id

      assert [%{name: "Ty Franck"}] =
               Person
               |> Repo.get!(person.id)
               |> Repo.preload(:narrators)
               |> Map.fetch!(:narrators)
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
            "new" => %{
              "series_id" => "",
              "series" => %{"name" => "Earthsea"},
              "book_number" => "1"
            }
          },
          "book_universes_sort" => ["new"],
          "book_universes" => %{
            "new" => %{"universe_id" => "", "universe" => %{"name" => "Hainish"}}
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
            "new" => %{"narrator_id" => "", "narrator" => %{"name" => "Kate Reading"}}
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
