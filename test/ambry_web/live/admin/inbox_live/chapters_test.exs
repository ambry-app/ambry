defmodule AmbryWeb.Admin.InboxLive.ChaptersTest do
  @moduledoc """
  Chapter confirmation as part of inbox curation — 1h's last box.

  The form states what the files carry (from the probe, no re-read) in one
  editable card, and imports titles the evidence way: a ticked ASIN-bearing
  record grows a chip, the fetched titles render into the rows, and Take —
  only offered when the counts match — applies through `Draft.Edit`, which
  the importer honors.
  """
  use AmbryWeb.ConnCase, async: false
  use Patch

  import Phoenix.ConnTest, except: [patch: 3]
  import Phoenix.LiveViewTest

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Tier
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.Provider
  alias Ambry.Repo

  setup :register_and_log_in_admin_user

  # A two-file release, so the probe stages two file-boundary markers.
  defp chaptered_item do
    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    release = Path.join(root, "Chaptered Book")
    File.mkdir_p!(release)
    Enum.each(["01.mp3", "02.mp3"], &File.cp!(valid_audio(:mp3), Path.join(release, &1)))

    {:ok, _counts} = Inbox.discover(root)
    {[item], false} = Inbox.list_items(filter: "Chaptered Book")
    {:ok, item} = Inbox.probe_item(item)

    # Probing enqueues matching, and `testing: :manual` means it never runs —
    # the leftover job would make the form refuse every event as busy.
    Repo.delete_all(Oban.Job)

    {:ok, item} = Inbox.prepare_draft(item)
    item
  end

  defp with_recording_record(item) do
    record = %{
      "source" => "provider:audible",
      "provider_name" => "Audible",
      "id" => "B08BKGYQXW",
      "asin" => "B08BKGYQXW",
      "title" => "Chaptered Book",
      "narrators" => ["Jeff Hays"],
      "score" => 1.0,
      # already full, so ticking it doesn't reach for a live provider
      "hydrated" => true
    }

    item
    |> InboxItem.changeset(%{
      matches: %{"recording" => %{"candidates" => [record], "confidence" => 1.0}}
    })
    |> Repo.update!()
  end

  defp patch_audnexus do
    patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B08BKGYQXW", _config ->
      {:ok,
       %Provider.Chapters{
         provider: "audnexus",
         asin: "B08BKGYQXW",
         chapters: [
           %Provider.Chapter{title: "The Dungeon Opens", start_offset_ms: 0},
           %Provider.Chapter{title: "Princess Donut", start_offset_ms: 1_000}
         ]
       }}
    end)
  end

  describe "the editor" do
    test "states what the files carry and renders editable rows, from the default state",
         %{conn: conn} do
      item = chaptered_item()

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "form#chapters-form")
      # two file-boundary rows, open by default because the list is short
      assert view
             |> element("#chapters-form")
             |> render() =~ "[chapters]"
    end

    # A change event from the chapters form is the operator touching the
    # rows — that is curation, and curation survives reseeds.
    test "typing a row curates the decision", %{conn: conn} do
      item = chaptered_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#chapters-form", %{
        "inbox_item" => %{
          "draft" => %{
            "recording" => %{
              "chapters" => %{
                "chapters" => %{
                  "0" => %{"time" => "0", "title" => "Prologue"}
                }
              }
            }
          }
        }
      })
      |> render_change()

      chapters = Inbox.get_item!(item.id).draft.recording.chapters
      assert chapters.curated
      assert [%{title: "Prologue"} | _rest] = chapters.chapters
    end
  end

  describe "title chips" do
    test "a ticked ASIN record offers its titles, and Apply pours them onto the staged markers",
         %{conn: conn} do
      patch_audnexus()
      item = chaptered_item() |> with_recording_record()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")
      # the files' own list is always on offer; a record's titles are not,
      # until its record is ticked
      refute has_element?(view, "button[phx-click='fetch-chapter-titles']")

      # tick the record — the evidence panel is the search
      view
      |> element("[phx-click='toggle-source'][phx-value-id='B08BKGYQXW']")
      |> render_click()

      assert has_element?(view, "#chapter-title-chips")

      view |> element("button[phx-click='fetch-chapter-titles']") |> render_click()
      html = render_async(view)
      # the proposed titles render into the rows, and the counts match
      assert html =~ "The Dungeon Opens"
      assert html =~ "shows how its title lands"

      view |> element("button[phx-click='apply-chapter-titles']") |> render_click()

      chapters = Inbox.get_item!(item.id).draft.recording.chapters
      assert chapters.curated
      assert Enum.map(chapters.chapters, & &1.title) == ["The Dungeon Opens", "Princess Donut"]
      assert Enum.all?(chapters.chapters, &(&1.title_source == :provider))
      # markers untouched: still the files' own boundaries
      assert chapters.chapter_marker_source == :file_boundaries
    end

    test "a mismatched count is shown but can't be taken", %{conn: conn} do
      patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B08BKGYQXW", _config ->
        {:ok,
         %Provider.Chapters{
           provider: "audnexus",
           asin: "B08BKGYQXW",
           chapters: [%Provider.Chapter{title: "Only One", start_offset_ms: 0}]
         }}
      end)

      item = chaptered_item() |> with_recording_record()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("[phx-click='toggle-source'][phx-value-id='B08BKGYQXW']")
      |> render_click()

      view |> element("button[phx-click='fetch-chapter-titles']") |> render_click()
      html = render_async(view)

      assert html =~ "1 title for 2 markers"
      assert html =~ "only taken when the counts match"
      refute has_element?(view, "button[phx-click='apply-chapter-titles']")
    end
  end

  # The draft-side half of the marker-honesty rule the media changeset has
  # always enforced: a nudged time makes the timeline the operator's.
  describe "moving a staged marker" do
    test "records the timeline as manual", %{conn: conn} do
      item = chaptered_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> form("#chapters-form", %{
        "inbox_item" => %{
          "draft" => %{
            "recording" => %{
              "chapters" => %{
                "chapters" => %{"0" => %{"time" => "12.5"}}
              }
            }
          }
        }
      })
      |> render_change()

      chapters = Inbox.get_item!(item.id).draft.recording.chapters
      assert chapters.chapter_marker_source == :manual
      assert chapters.curated
    end
  end

  # The card was the one decision in the tree wearing no rail and offering no
  # way to agree with it: an operator who wanted exactly what the files carry
  # could only reach `:reviewed` by editing a row, so agreeing cost a
  # pointless edit and disagreeing was the only settled state.
  describe "taking the files' own list" do
    test "the card wears the decision rail", %{conn: conn} do
      item = chaptered_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      # seeded approved and untouched — the machine settled it, nobody looked
      assert has_element?(view, "#chapters .border-blue-400\\/70")
    end

    test "the files are a chip, chosen while the rows still match them", %{conn: conn} do
      item = chaptered_item()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      assert has_element?(view, "button[phx-click='take-file-chapters']")

      assert view
             |> element("button[phx-click='take-file-chapters']")
             |> render() =~ "fa-check"
    end

    test "taking it settles the decision without touching a row", %{conn: conn} do
      item = chaptered_item()
      before = Inbox.get_item!(item.id).draft.recording.chapters
      refute before.curated

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view |> element("button[phx-click='take-file-chapters']") |> render_click()

      chapters = Inbox.get_item!(item.id).draft.recording.chapters
      assert chapters.curated
      assert Tier.of(chapters) == :reviewed
      # the rows are the files' own, unchanged — this is agreement, not an edit
      assert Enum.map(chapters.chapters, & &1.title) ==
               Enum.map(before.chapters, & &1.title)

      assert has_element?(view, "#chapters .border-brand-dark\\/60")
    end

    # Taking it after a merge is the way back to the machine's value that
    # every other decision has.
    test "it restores the files' titles after provider ones were poured on", %{conn: conn} do
      patch_audnexus()
      item = chaptered_item() |> with_recording_record()

      {:ok, view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      view
      |> element("[phx-click='toggle-source'][phx-value-id='B08BKGYQXW']")
      |> render_click()

      view |> element("button[phx-click='fetch-chapter-titles']") |> render_click()
      render_async(view)
      view |> element("button[phx-click='apply-chapter-titles']") |> render_click()

      assert ["The Dungeon Opens" | _rest] =
               Enum.map(Inbox.get_item!(item.id).draft.recording.chapters.chapters, & &1.title)

      view |> element("button[phx-click='take-file-chapters']") |> render_click()

      chapters = Inbox.get_item!(item.id).draft.recording.chapters
      refute "The Dungeon Opens" in Enum.map(chapters.chapters, & &1.title)
      assert chapters.curated
    end
  end

  # The operator's question when the rail was missing: it looked like it
  # wasn't a decision at all. It always was one, and always counted.
  describe "the settled count" do
    test "chapters are one of the decisions the footer counts", %{conn: conn} do
      item = chaptered_item()

      {:ok, _view, _html} = live(conn, ~p"/admin/inbox/#{item}")

      draft = Inbox.get_item!(item.id).draft
      with_chapters = Draft.progress(draft)
      without = Draft.progress(put_in(draft.recording.chapters, nil))

      assert with_chapters.total == without.total + 1
      assert with_chapters.resolved == without.resolved + 1
    end
  end
end
