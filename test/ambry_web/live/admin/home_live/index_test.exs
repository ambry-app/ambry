defmodule AmbryWeb.Admin.HomeLive.IndexTest do
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    test "renders admin dashboard with all stats", %{conn: conn} do
      person1 = :person |> build() |> with_thumbnails() |> insert()
      person2 = :person |> build() |> with_thumbnails() |> insert()

      author = insert(:author, person: person1)
      narrator = insert(:narrator, person: person2)
      series = insert(:series)

      book =
        insert(:book,
          book_authors: [%{author: author}],
          series_books: [%{series: series, book_number: 1}]
        )

      :media
      |> build(
        status: :ready,
        book: book,
        media_narrators: [%{narrator: narrator}]
      )
      |> with_thumbnails()
      |> with_source_files()
      |> insert()
      |> with_output_files()

      {:ok, view, html} = live(conn, ~p"/admin")

      assert html =~ "Overview"

      assert has_element?(view, "a[href='/admin/people']")
      assert has_element?(view, "a[href='/admin/books']")
      assert has_element?(view, "a[href='/admin/series']")
      assert has_element?(view, "a[href='/admin/media']")
      assert has_element?(view, "a[href='/admin/audit']")
      assert has_element?(view, "a[href='/admin/users']")

      assert has_element?(view, "[data-role='author-count']", "1")
      assert has_element?(view, "[data-role='narrator-count']", "1")
      assert has_element?(view, "[data-role='book-count']", "1")
      assert has_element?(view, "[data-role='series-count']", "1")
      assert has_element?(view, "[data-role='media-count']", "1")
      assert has_element?(view, "[data-role='file-count']", "4")
      assert has_element?(view, "[data-role='user-count']", "1")
    end

    test "updates stats in realtime when data changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "[data-role='author-count']", "0")

      author = insert(:author)
      author.person |> Ambry.People.PubSub.PersonCreated.new() |> Ambry.PubSub.broadcast()
      ensure_all_messages_handled(view.pid)

      assert has_element?(view, "[data-role='author-count']", "1")
    end
  end
end
