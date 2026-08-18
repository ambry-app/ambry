defmodule AmbryWeb.Admin.BookLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders books index with empty state when no books exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/books")

      assert html =~ "Books"
      assert has_element?(view, "[data-role='empty-message']")
    end

    test "renders list of books", %{conn: conn} do
      author = insert(:author, person: build(:person))
      series = insert(:series)

      book =
        insert(:book,
          title: "Test Book",
          book_authors: [%{author: author}],
          series_books: [%{series: series, book_number: 1}]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      assert has_element?(view, "[data-role='book-title']", book.title)
      assert has_element?(view, "[data-role='book-authors']", author.name)
      assert has_element?(view, "[data-role='book-series']", "#{series.name} #1")
    end

    test "updates list in realtime when books change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/books")

      # Initially no books
      assert has_element?(view, "[data-role='empty-message']")

      # Create a new book
      author = insert(:author, person: build(:person))
      book = insert(:book, title: "New Book", book_authors: [%{author: author}])
      book |> Ambry.Books.PubSub.BookCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='book-title']", book.title)

      # Update the book
      {:ok, updated_book} = Ambry.Books.update_book(book, %{title: "Updated Book"})
      updated_book |> Ambry.Books.PubSub.BookUpdated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='book-title']", "Updated Book")
      refute has_element?(view, "[data-role='book-title']", "New Book")

      # Delete the book
      {:ok, _} = Ambry.Books.delete_book(updated_book)
      updated_book |> Ambry.Books.PubSub.BookDeleted.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='empty-message']")
      refute has_element?(view, "[data-role='book-title']", "Updated Book")
    end
  end

  describe "Delete" do
    test "can delete a book that has no media", %{conn: conn} do
      book = insert(:book, title: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      assert has_element?(view, "[data-role='book-title']", book.title)

      view
      |> element("[data-role='delete-book']")
      |> render_click()

      refute has_element?(view, "[data-role='book-title']", book.title)
      assert has_element?(view, "[data-role='empty-message']")
      assert render(view) =~ "Book deleted successfully"
    end

    test "cannot delete a book that has media", %{conn: conn} do
      book = insert(:book, title: "Has Media")
      insert(:media, book: book)

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      assert has_element?(view, "[data-role='book-title']", book.title)

      view
      |> element("[data-role='delete-book']")
      |> render_click()

      # Book should still be visible
      assert has_element?(view, "[data-role='book-title']", book.title)
      assert render(view) =~ "Can&#39;t delete book because it has audiobooks"
    end
  end

  describe "Search" do
    test "filters books by search query", %{conn: conn} do
      book1 = insert(:book, title: "Unique Book Title")
      book2 = insert(:book, title: "Another Book")

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      # Initially shows all books
      assert has_element?(view, "[data-role='book-title']", book1.title)
      assert has_element?(view, "[data-role='book-title']", book2.title)

      # Search for specific book
      view
      |> form("[data-role='search-form']")
      |> render_submit(%{search: %{query: "Unique"}})

      # Should only show matching book
      assert has_element?(view, "[data-role='book-title']", book1.title)
      refute has_element?(view, "[data-role='book-title']", book2.title)
    end
  end

  describe "Sort" do
    test "sorts books by different fields", %{conn: conn} do
      _book1 = insert(:book, title: "A Book", inserted_at: ~N[2023-01-01 00:00:00])
      _book2 = insert(:book, title: "B Book", inserted_at: ~N[2023-02-01 00:00:00])

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      # Default sort is inserted_at desc, so newer book should be first
      titles =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role=book-title]")
        |> Floki.text(sep: "|")
        |> String.split("|")

      assert titles == ["B Book", "A Book"]

      # Sort by title ascending
      view
      |> element("[data-role=sort-button][phx-value-field=title]")
      |> render_click()

      titles =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role=book-title]")
        |> Floki.text(sep: "|")
        |> String.split("|")

      assert titles == ["A Book", "B Book"]

      # Click again for descending
      view
      |> element("[data-role=sort-button][phx-value-field=title]")
      |> render_click()

      titles =
        view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-role=book-title]")
        |> Floki.text(sep: "|")
        |> String.split("|")

      assert titles == ["B Book", "A Book"]
    end
  end

  describe "Pagination" do
    test "says which rows these are and how many there are", %{conn: conn} do
      for i <- 1..3, do: insert(:book, title: "Book #{i}")

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      # One page holds them all, so there is nothing to page through and no
      # bar to say so.
      refute has_element?(view, "[data-role=pagination]")
    end

    test "pages at fifty, and says where you are", %{conn: conn} do
      for i <- 1..51, do: insert(:book, title: "Book #{String.pad_leading(to_string(i), 3, "0")}")

      {:ok, view, _html} = live(conn, ~p"/admin/books?sort=title")

      assert view |> element("[data-role=pagination-range]") |> render() =~
               "Showing 1 to 50 of 51"

      assert view |> element("[data-role=pagination-page]") |> render() =~ "Page 1 of 2"
      assert length(titles(view)) == 50

      view |> element("[data-role=pagination] a", "Next") |> render_click()

      assert view |> element("[data-role=pagination-range]") |> render() =~
               "Showing 51 to 51 of 51"

      assert view |> element("[data-role=pagination-page]") |> render() =~ "Page 2 of 2"
      assert titles(view) == ["Book 051"]
    end

    test "counts under the filter it is listing with", %{conn: conn} do
      insert(:book, title: "Findable")
      insert(:book, title: "Other")

      {:ok, view, _html} = live(conn, ~p"/admin/books?filter=Findable&page=2")

      # Page 2 of a one-result search: the range collapses rather than
      # claiming rows it doesn't have, and the total describes the search.
      assert view |> element("[data-role=pagination-range]") |> render() =~ "Nothing on this page"
      assert view |> element("[data-role=pagination-page]") |> render() =~ "Page 2 of 1"
    end

    test "a live update does not throw the operator's sort away", %{conn: conn} do
      insert(:book, title: "B Book")
      insert(:book, title: "A Book")

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      view |> element("[data-role=sort-button][phx-value-field=title]") |> render_click()
      assert titles(view) == ["A Book", "B Book"]

      # Anything at all happening to any book used to rebuild the list out of
      # `%{"filter" => ..., "page" => ...}`, and a missing "sort" parses as
      # nil, so the list silently went back to the default ordering while the
      # address bar still said `?sort=title.asc`.
      insert(:book, title: "C Book")
      |> Ambry.Books.PubSub.BookCreated.new()
      |> Ambry.PubSub.broadcast()

      ensure_all_messages_handled(view.pid)

      assert titles(view) == ["A Book", "B Book", "C Book"]
    end
  end

  defp titles(view) do
    view
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("[data-role=book-title]")
    |> Floki.text(sep: "|")
    |> String.split("|")
  end
end
