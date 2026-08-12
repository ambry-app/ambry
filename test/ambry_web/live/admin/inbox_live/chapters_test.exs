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

      assert html =~ "one per file"
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

      {:ok, view, html} = live(conn, ~p"/admin/inbox/#{item}")
      refute html =~ "chapter-title-chips"

      # tick the record — the evidence panel is the search
      view
      |> element("[phx-click='toggle-source'][phx-value-id='B08BKGYQXW']")
      |> render_click()

      assert has_element?(view, "#chapter-title-chips")

      view |> element("#chapter-title-chips button") |> render_click()
      html = render_async(view)
      # the proposed titles render into the rows, and the counts match
      assert html =~ "The Dungeon Opens"
      assert html =~ "beside its row"

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

      view |> element("#chapter-title-chips button") |> render_click()
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
end
