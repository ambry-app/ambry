defmodule AmbryWeb.Admin.WatchLive.NewTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.Wanted

  setup :register_and_log_in_admin_user

  setup do
    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)
    :ok
  end

  defp offering(books) do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config -> {:ok, books} end)
  end

  defp velvet_knife do
    %Provider.Book{
      provider: "audible",
      id: "B0FKVNLXQS",
      title: "The Velvet Knife",
      asin: "B0FKVNLXQS",
      authors: [%{name: "Maureen Johnson", id: "a1", role: "author"}],
      narrators: [%{name: "Emily Ellet", id: "n1", role: "narrator"}],
      duration_seconds: 36_000,
      published: %Provider.PublishedDate{date: ~D[2026-09-29], display_format: :full}
    }
  end

  describe "New" do
    test "asks for something to search before it asks anyone", %{conn: conn} do
      offering([])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      html =
        view
        |> form("#watch-search-form", search: %{title: "", author: "", narrator: ""})
        |> render_submit()

      assert html =~ "Give it something to search for."
    end

    test "shows a preorder with its date and reader", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view
      |> form("#watch-search-form", search: %{title: "The Velvet Knife"})
      |> render_submit()

      html = render(view)

      assert html =~ "The Velvet Knife"
      assert html =~ "Emily Ellet"
      assert html =~ "Sep 29, 2026"
      assert has_element?(view, "[data-role='candidate-runtime']", "10h")
    end

    test "groups results under the provider that gave them", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      assert has_element?(view, "*", "Audible")
      assert has_element?(view, "[data-role='watch-candidate']")
    end

    test "says who answered, so nothing found and nobody asked look different",
         %{conn: conn} do
      offering([])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "Nothing"}) |> render_submit()

      assert has_element?(view, "*", "Who answered")
      assert has_element?(view, "*", "Nothing came back.")
    end

    test "marks a candidate that is already out rather than hiding it", %{conn: conn} do
      offering([
        %{velvet_knife() | published: %Provider.PublishedDate{date: ~D[2020-01-01]}}
      ])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "Old"}) |> render_submit()

      assert has_element?(view, "[data-role='candidate-date']", "already out")
    end

    test "watching a result keeps the provider's record", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      view |> element("[data-role='watch-this']") |> render_click()

      assert [watch] = Wanted.list_watches()
      assert watch.provider == "audible"
      assert watch.provider_id == "B0FKVNLXQS"
      assert watch.expected_release_date == ~D[2026-09-29]
      assert watch.edition.narrators == ["Emily Ellet"]
      assert watch.edition.asin == "B0FKVNLXQS"
      assert watch.edition.duration_seconds == 36_000
    end

    test "watching the same thing twice is an answer, not an error", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")
      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()
      view |> element("[data-role='watch-this']") |> render_click()

      {:ok, again, _html} = live(conn, ~p"/admin/watches/new")
      again |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      assert {:error, {:live_redirect, %{to: "/admin/watches"}}} =
               again |> element("[data-role='watch-this']") |> render_click()

      # The point: it lands on the list rather than on a form telling the
      # operator off, and there is still exactly one watch.
      assert length(Wanted.list_watches()) == 1
    end
  end
end
