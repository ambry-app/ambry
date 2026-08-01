defmodule AmbryWeb.Admin.MediaLive.ChaptersImportTest do
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  # search completion chains the chapters fetch; drain both asyncs
  defp render_chained_async(view) do
    render_async(view)
    render_async(view)
  end

  defp insert_media do
    :media
    |> build(book: build(:book), chapters: [])
    |> with_source_files()
    |> insert()
  end

  defp patch_providers do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok,
       [
         %Provider.Book{
           provider: "audible",
           id: "B08BKGYQXW",
           asin: "B08BKGYQXW",
           title: "Dungeon Crawler Carl",
           narrators: [%Provider.Contributor{name: "Jeff Hays", role: "narrator"}]
         }
       ]}
    end)

    patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B08BKGYQXW", _config ->
      {:ok,
       %Provider.Chapters{
         provider: "audnexus",
         asin: "B08BKGYQXW",
         chapters: [
           %Provider.Chapter{title: "Chapter 1", start_offset_ms: 0},
           %Provider.Chapter{title: "Chapter 2", start_offset_ms: 1_500_250}
         ]
       }}
    end)
  end

  test "imports chapters through the provider facade", %{conn: conn} do
    patch_providers()
    media = insert_media()

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")

    html = render_chained_async(view)
    assert html =~ "Chapter 1"
    assert html =~ "Chapter 2"

    view
    |> form("form[phx-submit='import']", %{"import" => %{"use_chapters" => "true"}})
    |> render_submit()

    html = render(view)
    # chapter rows landed in the editor form with ms converted to seconds
    assert html =~ ~s(value="Chapter 2")
    assert html =~ ~s(value="1500.25")
  end

  # the async chapters task intentionally raises; capture its crash report
  @tag :capture_log
  test "renders chapter-fetch errors in the modal", %{conn: conn} do
    patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
      {:ok, [%Provider.Book{provider: "audible", id: "B000", asin: "B000", title: "X"}]}
    end)

    patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B000", _config ->
      {:error, :not_found}
    end)

    media = insert_media()

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")

    html = render_chained_async(view)
    assert html =~ "There was an error fetching chapters"
  end
end
