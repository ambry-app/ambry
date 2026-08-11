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
