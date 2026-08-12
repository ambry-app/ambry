defmodule AmbryWeb.Admin.MediaLive.ChaptersImportTest do
  @moduledoc """
  Importing chapter titles, the evidence way: no search of its own — a
  ticked record carrying an ASIN grows a chip, the chip fetches every
  chapter-capable provider on the registry, the alignment previews inline,
  and Apply pours the titles.

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

  defp insert_media(chapters) do
    book =
      insert(:book,
        title: "Dungeon Crawler Carl",
        book_authors: [
          build(:book_author,
            author: build(:author, name: "Matt Dinniman", person: build(:person))
          )
        ]
      )

    :media
    |> build(book: book, chapters: chapters)
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
    # The evidence search is the chip's only road: one recording-level hit
    # with an ASIN, no work-level records (so no editions fan-out).
    patch(Ambry.Metadata.Search, :books, fn _query, opts ->
      case Keyword.fetch!(opts, :level) do
        :recording ->
          {:ok, entry} = Ambry.Metadata.Registry.fetch("audible")

          books = [
            %Provider.Book{
              provider: "audible",
              id: "B08BKGYQXW",
              asin: "B08BKGYQXW",
              title: "Dungeon Crawler Carl",
              authors: [%Provider.Contributor{name: "Matt Dinniman", role: nil}],
              narrators: [%Provider.Contributor{name: "Jeff Hays", role: "narrator"}]
            }
          ]

          {[{entry, books}],
           [%{"id" => "audible", "name" => "Audible", "status" => "ok", "count" => 1}]}

        :work ->
          {[], []}
      end
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

  # Search, tick the one record, and land on the chip.
  defp tick_record(view) do
    view
    |> form("#research-recording", %{"title" => "Dungeon Crawler Carl"})
    |> render_submit()

    render_async(view)

    view
    |> element("[phx-click='toggle-evidence'][phx-value-id='B08BKGYQXW']")
    |> render_click()
  end

  test "a ticked record with an ASIN offers its titles as a chip", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())

    {:ok, view, html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    refute html =~ "chapter-title-chips"

    html = tick_record(view)

    assert html =~ "chapter-title-chips"
    assert html =~ "titles for"
  end

  test "the chip renders proposals into the rows, and Take pours the titles onto the recording's own markers",
       %{conn: conn} do
    patch_providers()
    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)

    view |> element("#chapter-title-chips button") |> render_click()
    html = render_async(view)

    # The proposed titles land beside the rows — the rows are the preview.
    assert html =~ "The Dungeon Opens"
    assert html =~ "Princess Donut"
    assert html =~ "shows how its title lands"

    html =
      view |> element("button[phx-click='apply-chapter-titles']") |> render_click()

    assert html =~ ~s(value="The Dungeon Opens")
    assert html =~ ~s(value="Princess Donut")

    # The markers are untouched: 1490 is the rip's, 1500.25 is Audible's.
    assert html =~ ~s(value="1490.0")
    refute html =~ ~s(value="1500.25")

    # Applied, the pending header is gone.
    refute has_element?(view, "[data-role='chapter-import']")
  end

  # An operator call: a provider list that doesn't pair one-to-one with the
  # markers is shown (the proposed column says where the lists diverge) but
  # can never be taken.
  test "titles are only taken when the counts match", %{conn: conn} do
    patch_providers()

    patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B08BKGYQXW", _config ->
      {:ok,
       %Provider.Chapters{
         provider: "audnexus",
         asin: "B08BKGYQXW",
         chapters: [
           %Provider.Chapter{title: "Opening Credits", start_offset_ms: 0},
           %Provider.Chapter{title: "The Dungeon Opens", start_offset_ms: 30_000},
           %Provider.Chapter{title: "Princess Donut", start_offset_ms: 1_500_250}
         ]
       }}
    end)

    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)
    view |> element("#chapter-title-chips button") |> render_click()
    html = render_async(view)

    assert html =~ "3 titles for 2 markers"
    assert html =~ "only taken when the counts match"
    refute has_element?(view, "button[phx-click='apply-chapter-titles']")

    # a stale or forged click must not pour a mismatched list either
    html = render_click(view, "apply-chapter-titles", %{})
    refute html =~ ~s(value="Opening Credits")
    assert html =~ ~s(value="Chapter 1")
  end

  test "saving records that the titles came from a provider", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)
    view |> element("#chapter-title-chips button") |> render_click()
    render_async(view)
    view |> element("button[phx-click='apply-chapter-titles']") |> render_click()

    view |> form("#media-form") |> render_submit()

    media = Ambry.Media.get_media!(media.id)
    assert Enum.map(media.chapters, & &1.title) == ["The Dungeon Opens", "Princess Donut"]
    assert Enum.all?(media.chapters, &(&1.title_source == :provider))

    # List-level provenance: which provider's list was poured, worn on the
    # cluster label the same way the narrators wear theirs.
    assert %{"source" => "provider:audnexus"} = Ambry.Provenance.entry(media, :chapters)
  end

  # Titles are not markers. A merge that quietly claimed the timeline came
  # from a provider would undo the one distinction the editor is built on.
  test "leaves the recorded marker source alone", %{conn: conn} do
    patch_providers()
    media = insert_media(markers())
    {:ok, media} = Ambry.Media.update_media(media, %{chapter_marker_source: :file_boundaries})

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)
    view |> element("#chapter-title-chips button") |> render_click()
    render_async(view)
    view |> element("button[phx-click='apply-chapter-titles']") |> render_click()
    view |> form("#media-form") |> render_submit()

    assert Ambry.Media.get_media!(media.id).chapter_marker_source == :file_boundaries
  end

  test "says so when there are no markers for the titles to land on", %{conn: conn} do
    patch_providers()
    media = insert_media([])

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)
    view |> element("#chapter-title-chips button") |> render_click()
    html = render_async(view)

    # zero markers is the count mismatch at its plainest
    assert html =~ "2 titles for 0 markers"
    refute has_element?(view, "button[phx-click='apply-chapter-titles']")
  end

  # the async chapters task intentionally raises; capture its crash report
  @tag :capture_log
  test "renders chapter-fetch failures in the pending block", %{conn: conn} do
    patch_providers()

    patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B08BKGYQXW", _config ->
      {:error, :not_found}
    end)

    media = insert_media(markers())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media.id}/edit")
    tick_record(view)
    view |> element("#chapter-title-chips button") |> render_click()
    html = render_async(view)

    assert html =~ "Audnexus"
    assert has_element?(view, "button[phx-click='cancel-chapter-import']")
  end
end
