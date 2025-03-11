defmodule AmbryWeb.Admin.SeriesLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders series index with empty state when no series exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/series")

      assert html =~ "Series"
      assert has_element?(view, "[data-role='empty-message']", "No series yet.")
    end

    test "renders list of series", %{conn: conn} do
      author = insert(:author, person: build(:person, name: "Test Author"))
      book = insert(:book, book_authors: [%{author: author}])

      series =
        insert(:series,
          name: "Test Series",
          series_books: [%{book: book, book_number: 1}]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/series")

      assert has_element?(view, "[data-role='series-name']", series.name)
      assert has_element?(view, "[data-role='series-authors']", "by #{author.name}")
      assert has_element?(view, "[data-role='series-book-count']", "1")
    end

    test "updates list in realtime when series change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/series")

      # Initially no series
      assert has_element?(view, "[data-role='empty-message']", "No series yet.")

      # Create a new series
      series = insert(:series, name: "New Series")
      series |> Ambry.Books.PubSub.SeriesCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='series-name']", series.name)

      # Update the series
      {:ok, updated_series} = Ambry.Books.update_series(series, %{name: "Updated Series"})
      updated_series |> Ambry.Books.PubSub.SeriesUpdated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='series-name']", "Updated Series")
      refute has_element?(view, "[data-role='series-name']", "New Series")

      # Delete the series
      {:ok, _} = Ambry.Books.delete_series(updated_series)
      updated_series |> Ambry.Books.PubSub.SeriesDeleted.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='empty-message']", "No series yet.")
      refute has_element?(view, "[data-role='series-name']", "Updated Series")
    end
  end

  describe "Delete" do
    test "can delete a series", %{conn: conn} do
      series = insert(:series, name: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/admin/series")

      assert has_element?(view, "[data-role='series-name']", series.name)

      view
      |> element("[data-role='delete-series']")
      |> render_click()

      refute has_element?(view, "[data-role='series-name']", series.name)
      assert has_element?(view, "[data-role='empty-message']", "No series yet.")
      assert render(view) =~ "Series deleted successfully"
    end
  end

  describe "Search" do
    test "filters series by search query", %{conn: conn} do
      series1 = insert(:series, name: "Unique Series Name")
      series2 = insert(:series, name: "Another Series")

      {:ok, view, _html} = live(conn, ~p"/admin/series")

      # Initially shows all series
      assert has_element?(view, "[data-role='series-name']", series1.name)
      assert has_element?(view, "[data-role='series-name']", series2.name)

      # Search for specific series
      view
      |> form("[data-role='search-form']")
      |> render_submit(%{search: %{query: "Unique"}})

      # Should only show matching series
      assert has_element?(view, "[data-role='series-name']", series1.name)
      refute has_element?(view, "[data-role='series-name']", series2.name)
    end
  end

  describe "Sort" do
    test "sorts series by different fields", %{conn: conn} do
      _series1 = insert(:series, name: "A Series", inserted_at: ~N[2023-01-01 00:00:00])
      _series2 = insert(:series, name: "B Series", inserted_at: ~N[2023-02-01 00:00:00])

      {:ok, view, _html} = live(conn, ~p"/admin/series")

      # Default sort is inserted_at desc, so newer series should be first
      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='series-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Series", "A Series"]

      # Sort by name ascending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='series-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["A Series", "B Series"]

      # Click again for descending
      view
      |> element("[data-role=sort-button][phx-value-field=name]")
      |> render_click()

      names =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role='series-name']")
        |> Enum.map(&Floki.text/1)

      assert names == ["B Series", "A Series"]
    end
  end
end
