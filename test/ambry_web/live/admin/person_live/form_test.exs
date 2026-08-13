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
    test "links a shared author through the autocomplete", %{conn: conn} do
      abraham =
        insert(:person,
          name: "Daniel Abraham",
          authors: [build(:author, name: "James S.A. Corey")]
        )

      [corey] = Ambry.Repo.preload(abraham, :authors).authors
      person = insert(:person, name: "Ty Franck")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      # Linking lives behind the pen-name hatch now: it is the composite
      # case, not the ordinary one. Offered while unticked too, because this
      # is how a person who is not yet an author becomes one.
      view
      |> element("button[phx-value-kind='author'][phx-click='reveal-credit']")
      |> render_click()

      # type to filter, then pick the option; in the browser the value-change
      # hook then fires a form change event
      html =
        view
        |> element("#person_link_author_id-input")
        |> render_change(%{"resolver" => %{"person_link_author_id" => "James"}})

      # an edit form is a pure picker — no new-record support
      refute html =~ "Create “"

      view |> element("#person_link_author_id-option-#{corey.id}") |> render_click()

      html = view |> form("#person-form", %{"person" => %{}}) |> render_change()
      assert html =~ "James S.A. Corey"

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

    test "linking the same author twice adds only one row", %{conn: conn} do
      abraham =
        insert(:person,
          name: "Daniel Abraham",
          authors: [build(:author, name: "James S.A. Corey")]
        )

      [corey] = Ambry.Repo.preload(abraham, :authors).authors
      person = insert(:person, name: "Ty Franck")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person.id}/edit")

      view
      |> element("button[phx-value-kind='author'][phx-click='reveal-credit']")
      |> render_click()

      for _try <- 1..2 do
        view
        |> element("#person_link_author_id-input")
        |> render_change(%{"resolver" => %{"person_link_author_id" => "James"}})

        view |> element("#person_link_author_id-option-#{corey.id}") |> render_click()

        view |> form("#person-form", %{"person" => %{}}) |> render_change()
      end

      view |> form("#person-form", %{"person" => %{}}) |> render_submit()

      person = People.get_person!(person.id)
      assert [%{author: %{name: "James S.A. Corey"}}] = person.author_people
    end
  end
end
