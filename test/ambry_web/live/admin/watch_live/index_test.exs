defmodule AmbryWeb.Admin.WatchLive.IndexTest do
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ambry.Wanted

  setup :register_and_log_in_admin_user

  defp watch(overrides \\ %{}) do
    {:ok, watch} =
      Wanted.create_watch(
        Map.merge(
          %{
            provider: "audible",
            provider_id: "B0FKVNLXQS",
            expected_release_date: ~D[2026-09-29],
            edition: %{
              title: "The Velvet Knife",
              authors: ["Maureen Johnson"],
              narrators: ["Emily Ellet"],
              publisher: "Harper Audio"
            }
          },
          overrides
        )
      )

    watch
  end

  describe "Index" do
    test "an empty list invites the operator to start one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      assert has_element?(view, "*", "Nothing on the horizon.")
    end

    test "shows the book, who wrote it and who reads it", %{conn: conn} do
      watch()

      {:ok, _view, html} = live(conn, ~p"/admin/watches")

      assert html =~ "The Velvet Knife"
      assert html =~ "Maureen Johnson"
      assert html =~ "Emily Ellet"
    end

    test "names the provider the record came from", %{conn: conn} do
      watch()

      {:ok, _view, html} = live(conn, ~p"/admin/watches")

      assert html =~ "Audible"
    end

    test "a passed date is badged, and says the date passed rather than that it is out",
         %{conn: conn} do
      watch(%{expected_release_date: ~D[2020-01-01]})

      {:ok, view, html} = live(conn, ~p"/admin/watches")

      assert has_element?(view, "[data-role='watch-due-badge']")
      assert html =~ "Date passed"
      refute html =~ "Released"
    end

    test "a future date is not badged as due", %{conn: conn} do
      watch(%{expected_release_date: ~D[2099-01-01]})

      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      refute has_element?(view, "[data-role='watch-due-badge']")
    end

    test "a watch with no date says so instead of showing nothing", %{conn: conn} do
      watch(%{expected_release_date: nil})

      {:ok, _view, html} = live(conn, ~p"/admin/watches")

      assert html =~ "No date announced"
    end

    test "marking it out settles the watch", %{conn: conn} do
      watch = watch(%{expected_release_date: ~D[2020-01-01]})

      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      view |> element("[data-role='mark-released']") |> render_click()

      assert Wanted.get_watch!(watch.id).status == :released
      refute has_element?(view, "[data-role='watch-due-badge']")
    end

    test "dismissing stops the nag without claiming it arrived", %{conn: conn} do
      watch = watch(%{expected_release_date: ~D[2020-01-01]})

      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      view |> element("[data-role='dismiss-watch']") |> render_click()

      assert Wanted.get_watch!(watch.id).status == :dismissed
      assert render(view) =~ "Not watching"
    end

    test "a settled watch can be picked back up", %{conn: conn} do
      watch = watch()
      {:ok, _} = Wanted.dismiss(watch)

      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      view |> element("[data-role='reopen-watch']") |> render_click()

      assert Wanted.get_watch!(watch.id).status == :upcoming
    end

    test "forgetting removes it entirely", %{conn: conn} do
      watch = watch()

      {:ok, view, _html} = live(conn, ~p"/admin/watches")

      view |> element("[data-role='delete-watch']") |> render_click()

      assert Wanted.list_watches() == []
      assert render(view) =~ "Nothing on the horizon."
      refute render(view) =~ watch.edition.title
    end
  end

  describe "Form" do
    test "shows what was chosen without offering to rewrite it", %{conn: conn} do
      watch = watch()

      {:ok, _view, html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      assert html =~ "The Velvet Knife"
      assert html =~ "Emily Ellet"
      refute html =~ ~s|name="watch[edition]|
    end

    test "the date can be corrected when a publisher moves it", %{conn: conn} do
      watch = watch()

      {:ok, view, _html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      view
      |> form("form", watch: %{expected_release_date: "2026-11-03"})
      |> render_submit()

      assert Wanted.get_watch!(watch.id).expected_release_date == ~D[2026-11-03]
    end

    test "a note survives the round trip", %{conn: conn} do
      watch = watch()

      {:ok, view, _html} = live(conn, ~p"/admin/watches/#{watch}/edit")

      view
      |> form("form", watch: %{note: "Preordered on the 12th"})
      |> render_submit()

      assert Wanted.get_watch!(watch.id).note == "Preordered on the 12th"
    end
  end
end
