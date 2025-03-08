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
      author = insert(:author)
      series = insert(:series)

      book =
        insert(:book,
          title: "Test Book",
          book_authors: [%{author: author}],
          series_books: [%{series: series, book_number: 1}]
        )

      {:ok, view, _html} = live(conn, ~p"/admin/books")

      assert has_element?(view, "[data-role='book-title']", book.title)
      assert has_element?(view, "[data-role='book-authors']", "by #{author.person.name}")
      assert has_element?(view, "[data-role='book-series']", "#{series.name} #1")
    end

    test "updates list in realtime when books change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/books")

      # Initially no books
      assert has_element?(view, "[data-role='empty-message']")

      # Create a new book
      author = insert(:author)
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
      assert render(view) =~ "Can&#39;t delete book because this book has uploaded media"
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
end
