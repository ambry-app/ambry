defmodule AmbryWeb.Admin.PersonLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders people index with empty state when no people exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/people")

      assert html =~ "Authors &amp; Narrators"
      assert has_element?(view, "[data-role='empty-message']", "No people yet.")
    end

    test "renders list of people", %{conn: conn} do
      person = insert(:person, name: "Test Person")

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-name']", person.name)
    end

    test "updates list in realtime when people change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/people")

      # Initially no people
      assert has_element?(view, "[data-role='empty-message']", "No people yet.")

      # Create a new person
      person = insert(:person, name: "New Person")
      person |> Ambry.People.PubSub.PersonCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='person-name']", person.name)

      # Update the person
      {:ok, updated_person} = Ambry.People.update_person(person, %{name: "Updated Person"})
      updated_person |> Ambry.People.PubSub.PersonUpdated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='person-name']", "Updated Person")
      refute has_element?(view, "[data-role='person-name']", "New Person")

      # Delete the person
      {:ok, _} = Ambry.People.delete_person(updated_person)
      updated_person |> Ambry.People.PubSub.PersonDeleted.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='empty-message']", "No people yet.")
      refute has_element?(view, "[data-role='person-name']", "Updated Person")
    end

    test "renders person aliases", %{conn: conn} do
      person =
        insert(:person,
          name: "Test Person",
          authors: [%{name: "Writing Alias"}],
          narrators: [%{name: "Narrating Alias"}]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-name']", person.name)
      assert has_element?(view, "[data-role='person-aliases']", "Writing Alias, Narrating Alias")
    end
  end

  describe "Delete" do
    test "cannot delete a person that has authored books", %{conn: conn} do
      author = insert(:author)
      insert(:book, book_authors: [%{author: author}])

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-name']", author.person.name)

      view
      |> element("[data-role='delete-person']")
      |> render_click()

      # Person should still be visible
      assert has_element?(view, "[data-role='person-name']", author.person.name)
      assert render(view) =~ "Can&#39;t delete person because they have authored books"
    end

    test "cannot delete a person that has narrated media", %{conn: conn} do
      book = insert(:book, book_authors: [])
      narrator = insert(:narrator)
      insert(:media, book: book, media_narrators: [%{narrator: narrator}])

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-name']", narrator.person.name)

      view
      |> element("[data-role='delete-person']")
      |> render_click()

      # Person should still be visible
      assert has_element?(view, "[data-role='person-name']", narrator.person.name)
      assert render(view) =~ "Can&#39;t delete person because they have narrated media"
    end

    test "can delete a person with no books or media", %{conn: conn} do
      person = insert(:person, name: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-name']", person.name)

      view
      |> element("[data-role='delete-person']")
      |> render_click()

      refute has_element?(view, "[data-role='person-name']", person.name)
      assert has_element?(view, "[data-role='empty-message']", "No people yet.")
      assert render(view) =~ "Deleted #{person.name}"
    end
  end

  describe "Search" do
    test "filters people by search query", %{conn: conn} do
      person1 = insert(:person, name: "Unique Person Name")
      person2 = insert(:person, name: "Another Person")

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      # Initially shows all people
      assert has_element?(view, "[data-role='person-name']", person1.name)
      assert has_element?(view, "[data-role='person-name']", person2.name)

      # Search for specific person
      view
      |> form("#nav-header form")
      |> render_submit(%{search: %{query: "Unique"}})

      # Should only show matching person
      assert has_element?(view, "[data-role='person-name']", person1.name)
      refute has_element?(view, "[data-role='person-name']", person2.name)
    end
  end

  describe "Sort" do
    test "sorts people by different fields", %{conn: conn} do
      _person1 = insert(:person, name: "A Person", inserted_at: ~N[2023-01-01 00:00:00])
      _person2 = insert(:person, name: "B Person", inserted_at: ~N[2023-02-01 00:00:00])

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      # Default sort is inserted_at desc, so newer person should be first
      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='person-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Person", "A Person"]

      # Sort by name ascending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='person-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["A Person", "B Person"]

      # Click again for descending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='person-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Person", "A Person"]
    end
  end

  describe "Author and Narrator Counts" do
    test "shows book and media counts", %{conn: conn} do
      %{authors: [author], narrators: [narrator]} =
        insert(:person,
          name: "Test Person",
          authors: [%{name: "Test Author"}],
          narrators: [%{name: "Test Narrator"}]
        )

      book = insert(:book, book_authors: [%{author: author}])
      insert(:book, book_authors: [%{author: author}])
      insert(:media, book: book, media_narrators: [%{narrator: narrator}])

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-authored-count']", "2")
      assert has_element?(view, "[data-role='person-narrated-count']", "1")
    end

    test "shows missing description indicator", %{conn: conn} do
      no_desc = insert(:person, name: "No Description", description: nil)

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      assert has_element?(view, "[data-role='person-missing-description']")
      assert has_element?(view, "[data-role='person-name']", no_desc.name)
    end

    test "shows no missing description indicator", %{conn: conn} do
      no_desc = insert(:person, name: "Description", description: "A description")

      {:ok, view, _html} = live(conn, ~p"/admin/people")

      refute has_element?(view, "[data-role='person-missing-description']")
      assert has_element?(view, "[data-role='person-name']", no_desc.name)
    end
  end
end
