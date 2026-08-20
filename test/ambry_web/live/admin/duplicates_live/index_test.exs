defmodule AmbryWeb.Admin.DuplicatesLive.IndexTest do
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin_user

  describe "Index" do
    # The reassuring answer is the one that has to be trustworthy, so an
    # empty report says what it looked at. Without the count, "nothing found"
    # and "nothing ran" render identically.
    test "a clean library says so, and says what it checked", %{conn: conn} do
      insert(:person, name: "Becky Chambers")
      insert(:book, title: "A Psalm for the Wild-Built")

      {:ok, view, _html} = live(conn, ~p"/admin/duplicates")

      assert has_element?(view, "[data-role='all-clear']", "Nothing in the library is here twice")
      assert has_element?(view, "[data-role='scanned']", "1 person")
      assert has_element?(view, "[data-role='scanned']", "1 book")
    end

    test "a duplicated person is one set of two records", %{conn: conn} do
      kept = insert(:person, name: "Patricia Rodríguez")
      insert(:person, name: "Patricia Rodriguez")
      insert(:narrator, name: "Patricia Rodríguez", person: kept)

      {:ok, view, _html} = live(conn, ~p"/admin/duplicates")

      refute has_element?(view, "[data-role='all-clear']")
      assert has_element?(view, "[data-role='section-person']", "People")

      # One card, two rows in it.
      assert view |> element("[data-role='section-person']") |> render() =~ "duplicate-set"
      assert view |> render() |> count_of("data-role=\"duplicate-record\"") == 2
    end

    # The whole point of the counts: between two records of one name, the one
    # nothing references is the one you can act on.
    test "says which half nothing points at", %{conn: conn} do
      kept = insert(:person, name: "Patricia Rodríguez")
      insert(:person, name: "Patricia Rodriguez")
      insert(:narrator, name: "Patricia Rodríguez", person: kept)

      {:ok, view, _html} = live(conn, ~p"/admin/duplicates")

      assert has_element?(view, "[data-role='duplicate-record']", "1 narrator")
      assert has_element?(view, "[data-role='duplicate-record']", "Nothing points at this one")
    end

    test "each record links to where it is edited", %{conn: conn} do
      one = insert(:book, title: "The Princess Bride")
      two = insert(:book, title: "Princess Bride")

      {:ok, view, _html} = live(conn, ~p"/admin/duplicates")

      assert has_element?(view, ~s|a[href="/admin/books/#{one.id}/edit"]|)
      assert has_element?(view, ~s|a[href="/admin/books/#{two.id}/edit"]|)
    end

    # The report is a snapshot of a library that keeps moving, so it has to be
    # re-askable without a page load.
    test "reload picks up a duplicate created since the page opened", %{conn: conn} do
      insert(:book, title: "The Princess Bride")

      {:ok, view, _html} = live(conn, ~p"/admin/duplicates")
      assert has_element?(view, "[data-role='all-clear']")

      insert(:book, title: "Princess Bride")
      render_click(view, "reload")

      refute has_element?(view, "[data-role='all-clear']")
      assert has_element?(view, "[data-role='section-book']", "Books")
    end
  end

  defp count_of(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)
end
