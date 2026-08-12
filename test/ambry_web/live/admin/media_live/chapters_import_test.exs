defmodule AmbryWeb.Admin.MediaLive.ChaptersImportTest do
  @moduledoc """
  Importing chapter titles from a provider.

  The whole point of 1h is what this must *not* do: a provider's chapter
  timestamps describe its own retail edition, so they are read for their
  durations and then thrown away. Only the titles land.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Media.Media.Chapter
  alias Ambry.Metadata.Provider

  setup :register_and_log_in_admin_user

  # search completion chains the chapters fetch; drain both asyncs
  defp render_chained_async(view) do
    render_async(view)
    render_async(view)
  end

  defp insert_media(chapters \\ []) do
    :media
    |> build(book: build(:book), chapters: chapters)
    |> with_source_files()
    |> insert()
  end

  # Markers a few seconds off Audible's, which is what a rip of the same book
  # actually looks like.
  defp markers do
    [
      %Chapter{time: Decimal.new(0), title: "Chapter 1", title_source: :generated},
      %Chapter{time: Decimal.new("1490.0"), title: "Chapter 2", title_source: :generated}
    ]
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
           %Provider.Chapter{title: "The Dungeon Opens", start_offset_ms: 0},
           %Provider.Chapter{title: "Princess Donut", start_offset_ms: 1_500_250}
         ]
       }}
    end)
  end

  test "pours provider titles onto the recording's own markers", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")

    html = render_chained_async(view)
    # The preview shows the alignment, not just a wall of incoming names.
    assert html =~ "The Dungeon Opens"
    assert html =~ "Princess Donut"
    assert html =~ "titles land on a marker"

    view |> element("button[phx-click='import']") |> render_click()

    html = render(view)
    assert html =~ ~s(value="The Dungeon Opens")
    assert html =~ ~s(value="Princess Donut")

    # The markers are untouched: 1490 is the rip's, 1500.25 is Audible's.
    assert html =~ ~s(value="1490.0")
    refute html =~ ~s(value="1500.25")
  end

  test "records that the titles came from a provider", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")
    render_chained_async(view)
    view |> element("button[phx-click='import']") |> render_click()

    view |> element("form#media-chapters-form") |> render_submit()

    chapters = Ambry.Media.get_media!(media.id).chapters
    assert Enum.map(chapters, & &1.title) == ["The Dungeon Opens", "Princess Donut"]
    assert Enum.all?(chapters, &(&1.title_source == :provider))
  end

  # Titles are not markers. A merge that quietly claimed the timeline came
  # from Audible would undo the one distinction this whole page is built on.
  test "leaves the recorded marker source alone", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())
    {:ok, media} = Ambry.Media.update_media(media, %{chapter_marker_source: :file_boundaries})

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")
    render_chained_async(view)
    view |> element("button[phx-click='import']") |> render_click()
    view |> element("form#media-chapters-form") |> render_submit()

    assert Ambry.Media.get_media!(media.id).chapter_marker_source == :file_boundaries
  end

  test "says so when there are no markers for the titles to land on", %{conn: conn} do
    patch_providers()
    media = insert_media()

    {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=audible")

    html = render_chained_async(view)
    assert html =~ "no markers yet"
    refute has_element?(view, "button[phx-click='import']")
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
