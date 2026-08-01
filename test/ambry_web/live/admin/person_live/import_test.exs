defmodule AmbryWeb.Admin.PersonLive.ImportTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  # The import form chains two asyncs (search completion starts the
  # author-details fetch), and render_async/1 can return between them —
  # a second call drains the chained async deterministically.
  defp render_chained_async(view) do
    render_async(view)
    render_async(view)
  end

  defp patch_rreading_glasses do
    author = %Provider.Author{
      provider: "rreading_glasses",
      id: "999015",
      name: "Matt Dinniman",
      description: "Writer and artist from Gig Harbor.",
      image_url: "https://images.gr-assets.com/authors/999015.jpg"
    }

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_authors, fn _query, _config ->
      {:ok, [author]}
    end)

    patch(Ambry.Metadata.Providers.RreadingGlasses, :author_details, fn "999015", _config ->
      {:ok, author}
    end)

    author
  end

  test "offers registry providers as import sources", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/people/new")

    assert html =~ "rreading-glasses"
    assert html =~ "Audnexus"
    refute html =~ "GoodReads"
  end

  test "imports author details through a provider", %{conn: conn} do
    patch_rreading_glasses()

    {:ok, view, _html} = live(conn, ~p"/admin/people/new?import=rreading_glasses")

    html = render_chained_async(view)
    assert html =~ "Matt Dinniman"
    assert html =~ "Writer and artist from Gig Harbor."

    view
    |> form("form[phx-submit='import']", %{
      "import" => %{"use_name" => "true", "use_description" => "true", "use_image" => "true"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Matt Dinniman"
    assert html =~ ~s(value="https://images.gr-assets.com/authors/999015.jpg")
  end

  test "unknown provider in the URL just closes the import modal", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/people/new?import=bogus")

    refute html =~ "Import Author/Narrator"
  end

  test "Re-fetch bypasses the cache for details too, not just the search", %{conn: conn} do
    author = patch_rreading_glasses()

    {:ok, view, _html} = live(conn, ~p"/admin/people/new?import=rreading_glasses")
    render_chained_async(view)

    # both responses are cached now; the provider module is out of the loop
    restore(Ambry.Metadata.Providers.RreadingGlasses)

    fresh = %{author | image_url: "https://images.gr-assets.com/authors/999015-fresh.jpg"}

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_authors, fn _query, _config ->
      {:ok, [fresh]}
    end)

    patch(Ambry.Metadata.Providers.RreadingGlasses, :author_details, fn "999015", _config ->
      {:ok, fresh}
    end)

    view
    |> form("form[phx-submit='search']", %{"search" => %{"query" => "matt dinniman"}})
    |> render_submit(%{"refresh" => "true"})

    html = render_chained_async(view)
    assert html =~ "999015-fresh.jpg"
  end

  test "renders provider errors in the modal", %{conn: conn} do
    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_authors, fn _query, _config ->
      {:error, :nxdomain}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/people/new?import=rreading_glasses")

    html = render_async(view)
    assert html =~ "There was an error searching"
  end
end
