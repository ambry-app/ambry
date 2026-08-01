defmodule AmbryWeb.Admin.BookLive.ProviderImportTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  defp result_book do
    %Provider.Book{
      provider: "rreading_glasses",
      id: "76027608",
      title: "Dungeon Crawler Carl",
      cover_url: "https://images.gr-assets.com/books/54659324.jpg",
      published: %Provider.PublishedDate{date: ~D[2020-09-21], display_format: :full},
      authors: [%Provider.Contributor{id: "999015", name: "Matt Dinniman", role: "author"}],
      series: [%Provider.Series{id: "309211", name: "Dungeon Crawler Carl", number: "1"}]
    }
  end

  test "offers all providers with book search as import sources", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/books/new")

    assert html =~ "rreading-glasses"
    assert html =~ "Audible"
    refute html =~ "GoodReads"
  end

  test "imports a book through a work-level provider", %{conn: conn} do
    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, [result_book()]}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/books/new?import=rreading_glasses")

    html = render_async(view)
    assert html =~ "Dungeon Crawler Carl"
    assert html =~ "Missing author"
    assert html =~ "New series"

    view
    |> form("form[phx-submit='import']", %{
      "import" => %{
        "use_title" => "true",
        "use_published" => "true",
        "use_authors" => "true",
        "use_series" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ ~s(value="Dungeon Crawler Carl")
    assert html =~ ~s(value="2020-09-21")

    # the author and series were created and matched
    assert [%{name: "Matt Dinniman"}] = Ambry.Repo.all(Ambry.People.Person)
    assert [%{name: "Dungeon Crawler Carl"}] = Ambry.Repo.all(Ambry.Books.Series)
  end

  test "matches existing authors and series instead of duplicating", %{conn: conn} do
    person = insert(:person, name: "Matt Dinniman")
    insert(:author, person: person, name: "Matt Dinniman")
    with_search_index(person)

    series = insert(:series, name: "Dungeon Crawler Carl")
    insert(:series_book, series: series, book: insert(:book))
    with_search_index(series)

    patch(Ambry.Metadata.Providers.RreadingGlasses, :search_books, fn _query, _config ->
      {:ok, [result_book()]}
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/books/new?import=rreading_glasses")

    html = render_async(view)
    assert html =~ "Existing author"
    assert html =~ "Existing series"
  end
end
