defmodule AmbryWeb.Admin.PersonLive.FormTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.People
  alias Ambry.Provenance

  setup :register_and_log_in_admin_user

  describe "field-level provenance" do
    # Display, lock-toggling and pending previews live with the inline
    # provenance flag now â covered in evidence_test.exs.
    test "manually edited fields save with manual provenance, locked", %{conn: conn} do
      person = insert(:person, name: "Old Name")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view |> form("#person-form", %{"person" => %{"name" => "New Name"}}) |> render_submit()

      updated = People.get_person!(person.id)
      assert %{"source" => "manual", "locked" => true} = Provenance.entry(updated, :name)

      # untouched fields get no provenance entry
      assert Provenance.entry(updated, :image_path) == nil
    end
  end

  # `Author` and `Narrator` are credit NAMES, not roles. The form used to say
  # so out loud — two lists to populate, where having typed "Stephen King"
  # you were asked to add an author and the answer was "Stephen King" — so
  # the ordinary person now answers two checkboxes and types nothing.
  describe "credited as" do
    test "ticking writes creates an author under the person's own name", %{conn: conn} do
      person = insert(:person, name: "Stephen King")

      {:ok, view, html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      # nothing to fill in: the name is stated, not asked for
      refute html =~ "Writing as"

      view
      |> form("#person-form", %{"person" => %{"writes" => "true"}})
      |> render_submit()

      assert [%{name: "Stephen King"}] = People.get_person!(person.id).authors
    end

    test "ticking narrates creates a narrator the same way", %{conn: conn} do
      person = insert(:person, name: "Stephen King")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"narrates" => "true"}})
      |> render_submit()

      assert [%{name: "Stephen King"}] = People.get_person!(person.id).narrators
    end

    test "both is two ticks, not a special case", %{conn: conn} do
      person = insert(:person, name: "Stephen King")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"writes" => "true", "narrates" => "true"}})
      |> render_submit()

      person = People.get_person!(person.id)
      assert [%{name: "Stephen King"}] = person.authors
      assert [%{name: "Stephen King"}] = person.narrators
    end

    # The operator's call: nothing credits them, so nothing is protected, and
    # putting it back is a tick.
    test "unticking deletes the credit nothing is using", %{conn: conn} do
      person =
        insert(:person, name: "Stephen King", authors: [build(:author, name: "Stephen King")])

      [author] = Ambry.Repo.preload(person, :authors).authors

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"writes" => "false"}})
      |> render_submit()

      assert People.get_person!(person.id).authors == []
      refute Ambry.Repo.get(Ambry.People.Author, author.id)
    end

    # …but a credit a book is using is not the operator's to drop by
    # accident, and `delete_orphaned_authors/2` says so by name.
    test "unticking is refused while a book still credits them", %{conn: conn} do
      person =
        insert(:person, name: "Stephen King", authors: [build(:author, name: "Stephen King")])

      [author] = Ambry.Repo.preload(person, :authors).authors
      insert(:book, book_authors: [build(:book_author, author: author)])

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      html =
        view
        |> form("#person-form", %{"person" => %{"writes" => "false"}})
        |> render_submit()

      assert html =~ "in use by one or more books"
      assert [%{name: "Stephen King"}] = People.get_person!(person.id).authors
    end

    # Renaming Stephen King used to leave an author called Stephen King
    # behind, credited on every one of his books.
    test "renaming the person renames the credit that is their own name", %{conn: conn} do
      person =
        insert(:person,
          name: "Stephen King",
          authors: [build(:author, name: "Stephen King")],
          narrators: [build(:narrator, name: "Stephen King")]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"name" => "Richard Bachman"}})
      |> render_submit()

      person = People.get_person!(person.id)
      assert [%{name: "Richard Bachman"}] = person.authors
      assert [%{name: "Richard Bachman"}] = person.narrators
    end

    # A pen name is not their name, so it does not follow.
    test "a pen name is left alone when the person is renamed", %{conn: conn} do
      person =
        insert(:person, name: "J.K. Rowling", authors: [build(:author, name: "Robert Galbraith")])

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"name" => "Joanne Rowling"}})
      |> render_submit()

      assert [%{name: "Robert Galbraith"}] = People.get_person!(person.id).authors
    end

    # One of James S.A. Corey's two humans renaming themselves must not
    # rename James S.A. Corey.
    test "a shared pen name is never renamed by one of its people", %{conn: conn} do
      abraham =
        insert(:person, name: "Daniel Abraham", authors: [build(:author, name: "Daniel Abraham")])

      [shared] = Ambry.Repo.preload(abraham, :authors).authors
      franck = insert(:person, name: "Ty Franck")
      {:ok, _} = People.update_person(franck, %{author_people: [%{author_id: shared.id}]})

      abraham = People.get_person!(abraham.id)
      {:ok, view, _html} = live(conn, ~p"/admin/people/#{abraham.id}/edit")

      view
      |> form("#person-form", %{"person" => %{"name" => "Daniel James Abraham"}})
      |> render_submit()

      # the credit keeps its name, because it is not only his
      assert %{name: "Daniel Abraham"} = Ambry.Repo.get(Ambry.People.Author, shared.id)
    end

    # Emptying the list is not the same as not rendering it. Absent params
    # mean "leave the association alone" — Ecto's rule, and the right read
    # while the list is collapsed — but with it open and every row deleted,
    # absent means the operator deleted them, and the save has to say so.
    test "deleting every credit row actually deletes them", %{conn: conn} do
      person =
        insert(:person,
          name: "Foo",
          authors: [build(:author, name: "Foo"), build(:author, name: "Bar")]
        )

      # "Bar" is not "Foo", so this person opens revealed already
      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      # what the ✕ sends: the row's index on the drop param
      view
      |> element("#person-form")
      |> render_change(%{"person" => %{"author_people_drop" => ["0", "1"]}})

      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert People.get_person!(person.id).authors == []
    end

    # The same deletion, reached through the hatch instead of by divergence.
    # Absent params meant two different things depending on a flag the
    # template and the transform disagreed about, and this is the half where
    # the save quietly did nothing.
    test "deleting the only credit row after opening the hatch", %{conn: conn} do
      person =
        insert(:person, name: "Foo", authors: [build(:author, name: "Foo")])

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> element("button[phx-value-kind='author'][phx-click='reveal-credit']")
      |> render_click()

      view
      |> element("#person-form")
      |> render_change(%{"person" => %{"name" => "Foo", "author_people_drop" => ["0"]}})

      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert People.get_person!(person.id).authors == []
    end

    # A person whose data already disagrees with "their own name" opens with
    # the list showing: a pen name behind a control nobody clicked is a pen
    # name the operator cannot see.
    test "an existing pen name reveals itself without being asked", %{conn: conn} do
      person =
        insert(:person, name: "J.K. Rowling", authors: [build(:author, name: "Robert Galbraith")])

      {:ok, _view, html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      assert html =~ "Robert Galbraith"
      refute html =~ "Writes under a pen name?"
    end
  end

  describe "linking an existing author (composite pen names)" do
    # One control per row now: typing names a pen name, picking links this
    # row to one that already exists. The separate "or link an existing
    # author" box is gone — it was the same decision in a second costume.
    test "picking an existing author in a row links it", %{conn: conn} do
      abraham =
        insert(:person,
          name: "Daniel Abraham",
          authors: [build(:author, name: "James S.A. Corey")]
        )

      [corey] = Ambry.Repo.preload(abraham, :authors).authors
      person = insert(:person, name: "Ty Franck")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      # the hatch, then a row to put it in
      view
      |> element("button[phx-value-kind='author'][phx-click='reveal-credit']")
      |> render_click()

      view
      |> element("#person-form")
      |> render_change(%{"person" => %{"name" => "Ty Franck", "author_people_sort" => ["new"]}})

      html =
        view
        |> element("#author-0-resolver-input")
        |> render_change(%{"resolver" => %{"author-0-resolver" => "James"}})

      # an edit form is a picker and a namer, so both outcomes are offered
      assert html =~ "James S.A. Corey"

      view |> element("#author-0-resolver-option-#{corey.id}") |> render_click()
      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      person = People.get_person!(person.id)
      assert [%{author: %{name: "James S.A. Corey"} = author}] = person.author_people

      assert [%{name: "Daniel Abraham"}, %{name: "Ty Franck"}] =
               People.get_author!(author.id).people |> Enum.sort_by(& &1.name)
    end

    test "shows who a pen name is shared with", %{conn: conn} do
      author =
        insert(:author, name: "James S.A. Corey", person: build(:person, name: "Daniel Abraham"))

      franck = insert(:person, name: "Ty Franck")
      {:ok, _person} = People.update_person(franck, %{author_people: [%{author_id: author.id}]})

      %{author_people: [%{person_id: abraham_id}, _]} =
        People.get_author!(author.id) |> Ambry.Repo.preload(:author_people)

      {:ok, _view, html} = live(conn, ~p"/admin/people/#{abraham_id}/edit")

      assert html =~ "Shared pen name with Ty Franck"
    end

    # Typing over a saved row renames the author it points at. Emitting the
    # name without its id reads as "replace this author", which
    # `on_replace: :raise` turns into a crash rather than a rename.
    test "typing over a saved row renames that author", %{conn: conn} do
      person =
        insert(:person, name: "J.K. Rowling", authors: [build(:author, name: "Robert Galbrait")])

      [author] = Ambry.Repo.preload(person, :authors).authors

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> element("#author-0-resolver-input")
      |> render_change(%{"resolver" => %{"author-0-resolver" => "Robert Galbraith"}})

      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert %{name: "Robert Galbraith"} = Ambry.Repo.get(Ambry.People.Author, author.id)
      assert [%{name: "Robert Galbraith"}] = People.get_person!(person.id).authors
    end

    # THE ONE THAT MATTERED. Driving the resolver's own input in a test
    # exercises the component alone, and it dutifully clears its id and
    # keeps the typed text. A browser does something else: the parent form's
    # `validate` fires on the same keystroke, *before* the component's
    # round trip, so it arrives carrying the hidden inputs' PREVIOUS values
    # — and the parent then re-renders the component from its changeset,
    # putting the old name back in the box being typed into.
    #
    # So this sends what Chrome actually sends: stale id, stale name, and
    # the live text under `resolver[...]`. Before the fix it saved
    # "successfully" and changed nothing.
    test "renaming works from the params a browser really posts", %{conn: conn} do
      person = insert(:person, name: "Jason Pargin", authors: [build(:author, name: "Baz")])
      [baz] = Ambry.Repo.preload(person, :authors).authors
      [ap] = Ambry.Repo.preload(person, :author_people).author_people

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      stale = %{
        "person" => %{
          "name" => "Jason Pargin",
          "writes" => "true",
          "author_people" => %{
            "0" => %{
              "id" => to_string(ap.id),
              "author_id" => to_string(baz.id),
              "author" => %{"name" => "Baz"}
            }
          }
        },
        "resolver" => %{"author-0-resolver" => "David Wong"}
      }

      view |> element("#person-form") |> render_change(stale)
      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert %{name: "David Wong"} = Ambry.Repo.get(Ambry.People.Author, baz.id)
    end

    # …and the other half of the same params: an id the row did NOT have is
    # the operator picking from the list, which links rather than renames.
    # Told apart by the id alone, because the visible text says the picked
    # author's name either way.
    test "picking is told apart from typing by the id, not the text", %{conn: conn} do
      person = insert(:person, name: "Ty Franck", authors: [build(:author, name: "Typo")])
      [typo] = Ambry.Repo.preload(person, :authors).authors
      [ap] = Ambry.Repo.preload(person, :author_people).author_people
      corey = insert(:author, name: "James S.A. Corey")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      picked = %{
        "person" => %{
          "name" => "Ty Franck",
          "writes" => "true",
          "author_people" => %{
            "0" => %{
              "id" => to_string(ap.id),
              "author_id" => to_string(corey.id),
              "author" => %{"name" => "Typo"}
            }
          }
        },
        "resolver" => %{"author-0-resolver" => "James S.A. Corey"}
      }

      view |> element("#person-form") |> render_change(picked)
      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      # linked to Corey, and "Typo" — wanted by nobody now — is gone
      assert [%{name: "James S.A. Corey"}] = People.get_person!(person.id).authors
      assert %{name: "James S.A. Corey"} = Ambry.Repo.get(Ambry.People.Author, corey.id)
      refute Ambry.Repo.get(Ambry.People.Author, typo.id)
    end

    # The operator's own case: Jason Pargin credited as "Baz", with a book
    # already crediting that author. A rename does not unlink anything, so
    # the book is not in the way — but "does the book block it" is exactly
    # the question the row rewrite has to answer out loud.
    test "renaming works even when a book credits the author", %{conn: conn} do
      person = insert(:person, name: "Jason Pargin", authors: [build(:author, name: "Baz")])
      [baz] = Ambry.Repo.preload(person, :authors).authors
      insert(:book, book_authors: [build(:book_author, author: baz)])

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> element("#author-0-resolver-input")
      |> render_change(%{"resolver" => %{"author-0-resolver" => "David Wong"}})

      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert [%{name: "David Wong"}] = People.get_person!(person.id).authors
      # the same record, renamed — not a new author with the book left behind
      assert %{name: "David Wong"} = Ambry.Repo.get(Ambry.People.Author, baz.id)
    end

    # Relinking a row is safe for the same reason unticking is: the author it
    # pointed at is deleted only if nothing else wants it.
    test "picking a different author relinks the row and cleans up behind it", %{conn: conn} do
      person = insert(:person, name: "Ty Franck", authors: [build(:author, name: "Typo Name")])
      [typo] = Ambry.Repo.preload(person, :authors).authors
      other = insert(:author, name: "James S.A. Corey")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> element("#author-0-resolver-input")
      |> render_change(%{"resolver" => %{"author-0-resolver" => "James"}})

      view |> element("#author-0-resolver-option-#{other.id}") |> render_click()
      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      assert [%{name: "James S.A. Corey"}] = People.get_person!(person.id).authors
      refute Ambry.Repo.get(Ambry.People.Author, typo.id)
    end
  end
end
