defmodule AmbryWeb.Admin.BookLive.EvidenceTest do
  @moduledoc """
  The book form's inline evidence panel — the import form's model on a
  record that already exists. Replaced the per-provider import-modal tests
  when the modal died: one search fans out to every work-level provider,
  ticked records grow "Proposed" chips, and accepting a chip takes the value
  and records the source.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.Provenance

  setup :register_and_log_in_admin_user

  defp result_book do
    %Provider.Book{
      provider: "rreading_glasses",
      id: "76027608",
      title: "Dungeon Crawler Carl",
      cover_url: "https://images.gr-assets.com/books/54659324.jpg",
      published: %Provider.PublishedDate{date: ~D[2020-09-21], display_format: :full},
      authors: [%Provider.Contributor{id: "999015", name: "Matt Dinniman", role: "author"}],
      series: [%Provider.Series{id: "309211", name: "Dungeon Crawler Carl", number: "1"}]
    }
  end

  # The fan-out asks every enabled work-level provider; the mock answers for
  # the one whose record matters and lets the rest come up empty.
  defp patch_search(books \\ nil) do
    books = books || [result_book()]

    patch(Ambry.Metadata.Providers, :search_books, fn
      "rreading_glasses", _query, _opts -> {:ok, books}
      _other_provider, _query, _opts -> {:ok, []}
    end)
  end

  defp search(view, fields) do
    view |> form("#research-work", fields) |> render_submit()
    render_async(view)
  end

  defp tick_first_record(view) do
    view
    |> element(~s{[data-role="record"] input[type="checkbox"]})
    |> render_click()
  end

  test "searching lists every provider's records as tickable evidence", %{conn: conn} do
    patch_search()

    {:ok, view, html} = live(conn, ~p"/admin/books/new")

    # nothing is asked until the operator asks
    refute html =~ "data-role=\"record\""

    html = search(view, %{"title" => "Dungeon Crawler Carl"})

    assert html =~ "Dungeon Crawler Carl"
    assert html =~ "Matt Dinniman"
    # the outcome chips say who was asked
    assert html =~ "rreading-glasses: 1"
  end

  test "a provider that errors shows as unreachable, not as empty", %{conn: conn} do
    patch(Ambry.Metadata.Providers, :search_books, fn
      "rreading_glasses", _query, _opts -> {:error, :timeout}
      _other_provider, _query, _opts -> {:ok, []}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    html = search(view, %{"title" => "Dungeon Crawler Carl"})

    assert html =~ "couldn&#39;t be reached"
  end

  test "accepting a chip fills the field and saving records the provider, unlocked",
       %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})

    # ticking the record grows Proposed chips under the fields
    html = tick_first_record(view)
    assert html =~ "Proposed"

    view |> element(~s{#proposals-book_title button}) |> render_click()
    html = view |> element(~s{#proposals-book_published button}) |> render_click()

    assert html =~ ~s(value="Dungeon Crawler Carl")
    assert html =~ ~s(value="2020-09-21")
    # the pending provenance is announced before it's saved
    assert html =~ "will record rreading-glasses"

    view |> form("#book-form", %{"book" => %{}}) |> render_submit()

    book = Ambry.Repo.one!(Ambry.Books.Book)

    assert %{"source" => "provider:rreading_glasses", "locked" => false} =
             Provenance.entry(book, :title)

    assert %{"source" => "provider:rreading_glasses", "locked" => false} =
             Provenance.entry(book, :published)
  end

  test "editing an accepted value before saving makes it a manual edit again", %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    view |> element(~s{#proposals-book_title button}) |> render_click()
    view |> element(~s{#proposals-book_published button}) |> render_click()

    view
    |> form("#book-form", %{"book" => %{"title" => "Dungeon Crawler Carl, But Better"}})
    |> render_submit()

    book = Ambry.Repo.one!(Ambry.Books.Book)
    assert %{"source" => "manual", "locked" => true} = Provenance.entry(book, :title)
  end

  # Clicking the chip a value already came from announced a change that was
  # not one: the field says "from rreading-glasses" and one click on the chip
  # it is already wearing turned that amber.
  test "clicking the chip a saved value already came from is not news", %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    view |> element(~s{#proposals-book_title button}) |> render_click()
    view |> element(~s{#proposals-book_published button}) |> render_click()
    view |> element(~s{#proposals-authors button}) |> render_click()
    view |> form("#book-form", %{"book" => %{}}) |> render_submit()

    book = Ambry.Repo.one!(Ambry.Books.Book)
    assert %{"source" => "provider:rreading_glasses"} = Provenance.entry(book, :title)

    # back on the saved record, the chip is the one in use — clicking it again
    # changes nothing, so nothing is pending
    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    html = view |> element(~s{#proposals-book_title button}) |> render_click()

    refute html =~ "will record"
    assert html =~ "from rreading-glasses"
  end

  describe "going back to the saved value" do
    test "is offered once a field differs, and not before", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Carl")
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
      search(view, %{"title" => "Dungeon Crawler Carl"})
      tick_first_record(view)

      refute has_element?(view, ~s{#proposals-book_published button[phx-click="revert-field"]})

      view |> element(~s{#proposals-book_published button}) |> render_click()

      assert has_element?(view, ~s{#proposals-book_published button[phx-click="revert-field"]})
    end

    test "restores the field and drops what would have been recorded", %{conn: conn} do
      book = insert(:book, title: "Dungeon Crawler Karl")
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
      search(view, %{"title" => "Dungeon Crawler Carl"})
      tick_first_record(view)

      view |> element(~s{#proposals-book_title button}) |> render_click()

      html =
        view
        |> element(~s{#proposals-book_title button[phx-click="revert-field"]})
        |> render_click()

      refute html =~ "will record"

      view |> form("#book-form", %{"book" => %{}}) |> render_submit()

      book = Ambry.Books.get_book!(book.id)
      assert book.title == "Dungeon Crawler Karl"
      assert Provenance.entry(book, :title) == nil
    end

    # A form creating a record has nothing to go back to.
    test "is not offered on a new book", %{conn: conn} do
      patch_search()

      {:ok, view, _html} = live(conn, ~p"/admin/books/new")
      search(view, %{"title" => "Dungeon Crawler Carl"})
      tick_first_record(view)

      view |> element(~s{#proposals-book_title button}) |> render_click()

      refute has_element?(view, ~s{button[phx-click="revert-field"]})
    end
  end

  test "accepting entity chips creates the missing author and series", %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    view |> element(~s{#proposals-authors button}) |> render_click()
    html = view |> element(~s{#proposals-series button}) |> render_click()

    # the rows landed in the form
    assert html =~ "Matt Dinniman"

    assert [%{name: "Matt Dinniman"}] = Ambry.Repo.all(Ambry.People.Person)
    assert [%{name: "Dungeon Crawler Carl"}] = Ambry.Repo.all(Ambry.Books.Series)

    # the proposed series number came along
    assert html =~ ~s(value="1")
  end

  # The chip is green and ticked because the book already has that author.
  # Clicking it again credited them a second time, and a third, which is how
  # the same bug got the narrator chips removed from the audiobook form.
  test "an author the book already has is not offered again", %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    html = view |> element(~s{#proposals-authors button}) |> render_click()
    assert html =~ "Matt Dinniman"

    # nothing left to click: the chip reports what the record holds
    refute has_element?(view, ~s{#proposals-authors button})
    assert has_element?(view, ~s{#proposals-authors span}, "Matt Dinniman")

    # and the event itself is idempotent, for a page that still shows the old chip
    render_click(view, "accept-entity", %{"field" => "authors", "key" => "Matt Dinniman"})

    assert [%{name: "Matt Dinniman"}] = Ambry.Repo.all(Ambry.People.Person)
    assert view |> render() |> author_row_count() == 1
  end

  # Removing the row is what makes the chip an offer again, so it has to be an
  # offer that works: the ✕ leaves the row in the association marked for
  # replacement, and reading that list made the chip refuse to re-add the
  # author it had just removed.
  test "an author removed with the ✕ can be credited again from the chip", %{conn: conn} do
    patch_search()

    # A *saved* author, which is the whole difference: removing a row that
    # exists in the database leaves it in the association marked for
    # replacement, where an unsaved one simply disappears.
    person = insert(:person, name: "Matt Dinniman")
    author = insert(:author, name: "Matt Dinniman", person: person)
    book = insert(:book, title: "Dungeon Crawler Carl", book_authors: [])
    {:ok, book} = credit_author(book, author)

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    # the book already has them, so the chip is a statement
    refute has_element?(view, ~s{#proposals-authors button})

    html =
      view |> form("#book-form") |> render_change(%{"book" => %{"book_authors_drop" => ["0"]}})

    assert author_row_count(html) == 0
    # green is gone: the book no longer has them
    assert has_element?(view, ~s{#proposals-authors button})

    html = view |> element(~s{#proposals-authors button}) |> render_click()
    assert author_row_count(html) == 1
    refute has_element?(view, ~s{#proposals-authors button})
  end

  defp credit_author(book, author) do
    Ambry.Books.update_book(book, %{
      "book_authors" => %{"0" => %{"author_id" => to_string(author.id), "position" => "0"}}
    })
  end

  test "a series the book is already in is not offered again", %{conn: conn} do
    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    view |> element(~s{#proposals-series button}) |> render_click()
    refute has_element?(view, ~s{#proposals-series button})

    render_click(view, "accept-entity", %{"field" => "series", "key" => "Dungeon Crawler Carl"})

    assert [%{name: "Dungeon Crawler Carl"}] = Ambry.Repo.all(Ambry.Books.Series)
    assert view |> render() |> series_row_count() == 1
  end

  defp author_row_count(html) do
    html |> Floki.parse_document!() |> Floki.find("[name$='[author_id]']") |> length()
  end

  defp series_row_count(html) do
    html |> Floki.parse_document!() |> Floki.find("[name$='[series_id]']") |> length()
  end

  test "the record that filled fields at import is recognized: pre-ticked, and says what it gave",
       %{conn: conn} do
    book =
      insert(:book,
        title: "Dungeon Crawler Carl",
        field_provenance: %{
          "title" => %{
            "source" => "provider:rreading_glasses",
            "record" => "76027608",
            "locked" => false,
            "at" => "2026-08-01T00:00:00Z"
          },
          "published" => %{
            "source" => "provider:rreading_glasses",
            "record" => "76027608",
            "locked" => false,
            "at" => "2026-08-01T00:00:00Z"
          }
        }
      )

    patch_search()

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book.id}/edit")
    html = search(view, %{"title" => "Dungeon Crawler Carl"})

    # recognized from provenance refs: arrives ticked, wearing its note
    assert html =~ ~s(data-used="true")
    assert html =~ "filled published · title"

    # and its proposals are already on offer, no tick needed
    assert html =~ "Proposed"
  end

  test "an entity chip links the credited pen name, never the person behind it",
       %{conn: conn} do
    # Ty Franck writes as himself AND as half of James S.A. Corey; a record
    # credited to the pen name must link the pen name — never the person,
    # and never his first identity.
    import Ecto.Query, only: [from: 2]

    # Indexed by the triggers on insert; nothing has to ask for it.
    insert(:person,
      name: "Ty Franck",
      authors: [build(:author, name: "Ty Franck"), build(:author, name: "James S.A. Corey")]
    )

    book = %{
      result_book()
      | authors: [%Provider.Contributor{id: "1", name: "James S.A. Corey", role: "author"}]
    }

    patch_search([book])

    {:ok, view, _html} = live(conn, ~p"/admin/books/new")
    search(view, %{"title" => "Dungeon Crawler Carl"})
    tick_first_record(view)

    view |> element(~s{#proposals-book_title button}) |> render_click()
    view |> element(~s{#proposals-book_published button}) |> render_click()
    view |> element(~s{#proposals-authors button}) |> render_click()
    view |> form("#book-form", %{"book" => %{}}) |> render_submit()

    saved_book =
      Ambry.Repo.one!(from b in Ambry.Books.Book, where: b.title == "Dungeon Crawler Carl")

    corey = Ambry.Repo.one!(from a in Ambry.People.Author, where: a.name == "James S.A. Corey")

    assert [%{id: author_id}] = Ambry.Repo.preload(saved_book, :authors).authors
    assert author_id == corey.id

    # no duplicate person or identity was created
    assert [_ty_franck] = Ambry.Repo.all(Ambry.People.Person)
    assert length(Ambry.Repo.all(Ambry.People.Author)) == 2
  end
end
