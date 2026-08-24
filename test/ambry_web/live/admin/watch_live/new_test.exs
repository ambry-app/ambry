defmodule AmbryWeb.Admin.WatchLive.NewTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.ProviderConfig
  alias Ambry.Repo
  alias Ambry.Wanted

  setup :register_and_log_in_admin_user

  setup do
    Repo.insert!(%ProviderConfig{
      provider_id: "hardcover",
      enabled: true,
      config: %{"api_token" => "test-token"}
    })

    patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _query, _config -> {:ok, []} end)
    :ok
  end

  defp future_edition(title) do
    %Provider.Book{
      provider: "hardcover",
      id: title,
      title: title,
      published: %Provider.PublishedDate{date: ~D[2099-01-01], display_format: :full}
    }
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
      published: %Provider.PublishedDate{date: ~D[2099-09-29], display_format: :full}
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
      assert html =~ "Sep 29, 2099"
      assert has_element?(view, "[data-role='candidate-facts']", "10h")
    end

    # A work-level provider names the book a recording is of, and that is a
    # fact on the row now that nothing is grouped under it.
    test "a recording says which book a work-level provider says it is of", %{conn: conn} do
      offering([])

      patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _q, _c ->
        {:ok,
         [
           %Provider.Book{provider: "hardcover", id: "w1", title: "Neuromancer"},
           %Provider.Book{
             provider: "hardcover",
             id: "w2",
             title: "Neuromancer: The Graphic Novel"
           }
         ]}
      end)

      patch(Ambry.Metadata.Providers.Hardcover, :editions_bulk, fn _ids, _c ->
        {:ok, %{"w1" => [future_edition("Reissue")], "w2" => [future_edition("Adaptation")]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")
      view |> form("#watch-search-form", search: %{title: "Neuromancer"}) |> render_submit()

      assert has_element?(view, "[data-role='candidate-facts']", "Neuromancer")

      assert has_element?(
               view,
               "[data-role='candidate-facts']",
               "Neuromancer: The Graphic Novel"
             )
    end

    # Which database answered is a fact about the record, not a heading over a
    # group of them: one list, ranked once, each row saying where it came from.
    test "every result says which provider found it", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      assert has_element?(view, "[data-role='record-source']", "Audible")
      assert has_element?(view, "[data-role='watch-candidate']")
    end

    test "results from two providers are one ranked list, best first", %{conn: conn} do
      offering([velvet_knife()])

      patch(Ambry.Metadata.Providers.Hardcover, :search_books, fn _q, _c ->
        {:ok, [%Provider.Book{provider: "hardcover", id: "w1", title: "Something Else Entirely"}]}
      end)

      patch(Ambry.Metadata.Providers.Hardcover, :editions_bulk, fn _ids, _c ->
        {:ok, %{"w1" => [future_edition("Something Else Entirely")]}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")
      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      titles =
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.find("[data-role='watch-candidate']")
        |> Enum.map(&(&1 |> Floki.find("span.truncate") |> Floki.text() |> String.trim()))

      assert ["The Velvet Knife" | _rest] = titles
    end

    test "says who answered, so nothing found and nobody asked look different",
         %{conn: conn} do
      offering([])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "Nothing"}) |> render_submit()

      assert has_element?(view, "[data-role='provider-outcomes']", "Audible: 0")
      assert has_element?(view, "*", "Nothing upcoming found.")
    end

    test "a recording that is already out is not offered as a watch", %{conn: conn} do
      offering([
        %{velvet_knife() | published: %Provider.PublishedDate{date: ~D[2020-01-01]}}
      ])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "Old"}) |> render_submit()

      refute has_element?(view, "[data-role='watch-candidate']")
    end

    # Otherwise a book whose recordings are all decades old reads as a book
    # the provider does not have.
    test "says results were set aside rather than that nothing was found", %{conn: conn} do
      offering([
        %{velvet_knife() | published: %Provider.PublishedDate{date: ~D[2020-01-01]}}
      ])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "Old"}) |> render_submit()

      assert has_element?(view, "*", "1 already released not shown.")
      assert has_element?(view, "*", "Nothing upcoming found.")
    end

    test "watching a result keeps the provider's record", %{conn: conn} do
      offering([velvet_knife()])

      {:ok, view, _html} = live(conn, ~p"/admin/watches/new")

      view |> form("#watch-search-form", search: %{title: "The Velvet Knife"}) |> render_submit()

      view |> element("[data-role='watch-this']") |> render_click()

      assert [watch] = Wanted.list_watches()
      assert watch.provider == "audible"
      assert watch.provider_id == "B0FKVNLXQS"
      assert watch.expected_release_date == ~D[2099-09-29]
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
