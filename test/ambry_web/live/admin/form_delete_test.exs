defmodule AmbryWeb.Admin.FormDeleteTest do
  @moduledoc """
  §6's two homes for a delete, checked on the second one.

  Destroying a record is offered in exactly two places and the same two for
  every record type: the row in its list, and the form's sticky footer. Every
  list's half has had a test since it was written; the footer's half did not
  exist, and the lists had drifted into five ways of saying a delete had
  worked while nobody was comparing them.

  So this is one file across the forms rather than a test apiece: what is
  being checked is that they agree, and a test that lives beside one form
  cannot see that.
  """

  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Books
  alias Ambry.Media

  setup :register_and_log_in_admin_user

  describe "the footer's delete" do
    test "deletes a series and goes back to the list", %{conn: conn} do
      series = insert(:series, name: "Doomed")

      {:ok, view, _html} = live(conn, ~p"/admin/series/#{series}/edit")

      view |> element("[data-role='delete-series']") |> render_click()

      assert %{"info" => "Deleted Doomed."} = assert_redirect(view, ~p"/admin/series")
      assert_raise Ecto.NoResultsError, fn -> Books.get_series!(series.id) end
    end

    test "deletes a universe and goes back to the list", %{conn: conn} do
      universe = insert(:universe, name: "Doomed")

      {:ok, view, _html} = live(conn, ~p"/admin/universes/#{universe}/edit")

      view |> element("[data-role='delete-universe']") |> render_click()

      assert %{"info" => "Deleted Doomed."} = assert_redirect(view, ~p"/admin/universes")
      assert_raise Ecto.NoResultsError, fn -> Books.get_universe!(universe.id) end
    end

    test "deletes a set and goes back to the list", %{conn: conn} do
      group = insert(:recording_group, name: "Doomed")

      {:ok, view, _html} = live(conn, ~p"/admin/sets/#{group}/edit")

      view |> element("[data-role='delete-group']") |> render_click()

      assert %{"info" => "Deleted Doomed."} = assert_redirect(view, ~p"/admin/sets")
      assert_raise Ecto.NoResultsError, fn -> Media.get_recording_group!(group.id) end
    end

    test "deletes a person and goes back to the list", %{conn: conn} do
      person = insert(:person, name: "Doomed")

      {:ok, view, _html} = live(conn, ~p"/admin/people/#{person}/edit")

      view |> element("[data-role='delete-person']") |> render_click()

      assert %{"info" => "Deleted Doomed."} = assert_redirect(view, ~p"/admin/people")
      assert_raise Ecto.NoResultsError, fn -> Ambry.People.get_person!(person.id) end
    end

    test "forgets a watch and goes back to the list", %{conn: conn} do
      {:ok, watch} =
        Ambry.Wanted.create_watch(%{
          provider: "audible",
          provider_id: "B0FKVNLXQS",
          edition: %{title: "Doomed"}
        })

      {:ok, view, _html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      view |> element("[data-role='delete-watch']") |> render_click()

      assert_redirect(view, ~p"/admin/watches")
      assert_raise Ecto.NoResultsError, fn -> Ambry.Wanted.get_watch!(watch.id) end
    end

    test "deletes a book and goes back to the list", %{conn: conn} do
      book = insert(:book, title: "Doomed")

      {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

      view |> element("[data-role='delete-book']") |> render_click()

      assert %{"info" => "Deleted Doomed."} = assert_redirect(view, ~p"/admin/books")
      assert_raise Ecto.NoResultsError, fn -> Books.get_book!(book.id) end
    end
  end

  # The refusal has to reach the operator on the form as well, and say the
  # same thing the row says. A form that navigated away on a delete the
  # library refused would report the opposite of what happened.
  test "a refused delete keeps you on the form and says why", %{conn: conn} do
    book = insert(:book, title: "Has Audiobooks")
    insert(:media, book: book)

    {:ok, view, _html} = live(conn, ~p"/admin/books/#{book}/edit")

    html = view |> element("[data-role='delete-book']") |> render_click()

    assert html =~ "Has Audiobooks has audiobooks in the library."
    assert Books.get_book!(book.id)
  end

  # A record that does not exist yet cannot be destroyed, so the bar does not
  # offer it — rather than offering a button that would have to explain
  # itself.
  test "a new record's footer offers no delete", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/books/new")

    refute has_element?(view, "[data-role='delete-book']")
  end
end
