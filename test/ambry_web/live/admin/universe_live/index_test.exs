defmodule AmbryWeb.Admin.UniverseLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders universes index with empty state when no universes exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/universes")

      assert html =~ "Universes"
      assert has_element?(view, "[data-role='empty-message']", "No universes yet.")
    end

    test "renders list of universes", %{conn: conn} do
      book = insert(:book)

      universe =
        insert(:universe,
          name: "Test Universe",
          book_universes: [%{book: book}]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/universes")

      assert has_element?(view, "[data-role='universe-name']", universe.name)
      assert has_element?(view, "[data-role='universe-book-count']", "1")
    end

    test "updates list in realtime when universes change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/universes")

      # Initially no universes
      assert has_element?(view, "[data-role='empty-message']", "No universes yet.")

      # Create a new universe
      universe = insert(:universe, name: "New Universe")
      universe |> Ambry.Books.PubSub.UniverseCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='universe-name']", universe.name)

      # Update the universe
      {:ok, updated_universe} = Ambry.Books.update_universe(universe, %{name: "Updated Universe"})
      updated_universe |> Ambry.Books.PubSub.UniverseUpdated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='universe-name']", "Updated Universe")
      refute has_element?(view, "[data-role='universe-name']", "New Universe")

      # Delete the universe
      {:ok, _} = Ambry.Books.delete_universe(updated_universe)
      updated_universe |> Ambry.Books.PubSub.UniverseDeleted.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='empty-message']", "No universes yet.")
      refute has_element?(view, "[data-role='universe-name']", "Updated Universe")
    end
  end

  describe "Delete" do
    test "can delete a universe", %{conn: conn} do
      universe = insert(:universe, name: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/admin/universes")

      assert has_element?(view, "[data-role='universe-name']", universe.name)

      view
      |> element("[data-role='delete-universe']")
      |> render_click()

      refute has_element?(view, "[data-role='universe-name']", universe.name)
      assert has_element?(view, "[data-role='empty-message']", "No universes yet.")
      assert render(view) =~ "Universe deleted successfully"
    end
  end

  describe "Search" do
    test "filters universes by search query", %{conn: conn} do
      universe1 = insert(:universe, name: "Unique Universe Name")
      universe2 = insert(:universe, name: "Another Universe")

      {:ok, view, _html} = live(conn, ~p"/admin/universes")

      # Initially shows all universes
      assert has_element?(view, "[data-role='universe-name']", universe1.name)
      assert has_element?(view, "[data-role='universe-name']", universe2.name)

      # Search for specific universe
      view
      |> form("[data-role='search-form']")
      |> render_submit(%{search: %{query: "Unique"}})

      # Should only show matching universes
      assert has_element?(view, "[data-role='universe-name']", universe1.name)
      refute has_element?(view, "[data-role='universe-name']", universe2.name)
    end
  end

  describe "Sort" do
    test "sorts universes by different fields", %{conn: conn} do
      _universe1 = insert(:universe, name: "A Universe", inserted_at: ~N[2023-01-01 00:00:00])
      _universe2 = insert(:universe, name: "B Universe", inserted_at: ~N[2023-02-01 00:00:00])

      {:ok, view, _html} = live(conn, ~p"/admin/universes")

      # Default sort is inserted_at desc, so newer universes should be first
      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='universe-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Universe", "A Universe"]

      # Sort by name ascending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='universe-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["A Universe", "B Universe"]

      # Click again for descending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='universe-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Universe", "A Universe"]
    end
  end
end
