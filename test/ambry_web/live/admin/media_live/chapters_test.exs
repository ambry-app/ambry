defmodule AmbryWeb.Admin.MediaLive.ChaptersTest do
  @moduledoc """
  The chapter editor.

  Everything here is about the one distinction 1h introduced: a marker is a
  position the files stated, a title is a name from wherever the best one
  came from, and the editor has to keep saying which is which through every
  edit.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media
  alias Ambry.Media.Media.Chapter

  setup :register_and_log_in_admin_user

  defp media_with_chapters(chapters, attrs \\ []) do
    :media
    |> build([book: build(:book), chapters: chapters] ++ attrs)
    # A real copy in the media's own folder, so the source modal can probe
    # it — the relative fixture paths `with_source_files/1` writes are
    # unreadable by anything that actually opens the file.
    |> with_copied_source_files()
    |> insert()
  end

  defp chapter(time, title, source),
    do: %Chapter{time: Decimal.new(time), title: title, title_source: source}

  # The rendered rows as `{time, title}`, in the order they're drawn — which
  # is the order that decides what the generated floor calls each one.
  defp rendered_rows(html) do
    document = Floki.parse_document!(html)

    times = values(document, "input[name^='media[chapters]'][name$='[time]']")
    titles = values(document, "input[name^='media[chapters]'][name$='[title]']")

    Enum.zip(times, titles)
  end

  defp values(document, selector) do
    document |> Floki.find(selector) |> Enum.map(&(&1 |> Floki.attribute("value") |> hd()))
  end

  describe "the header" do
    test "says where the markers came from", %{conn: conn} do
      media =
        media_with_chapters([chapter(0, "Chapter 1", :generated)],
          chapter_marker_source: :file_boundaries
        )

      {:ok, _view, html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      assert html =~ "one per file"
      assert html =~ "1 generated"
    end

    test "is honest about a list that predates the field", %{conn: conn} do
      media = media_with_chapters([chapter(0, "Prologue", nil)])

      {:ok, _view, html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      assert html =~ "from before this was recorded"
    end
  end

  describe "editing" do
    # The rule the whole page is built on, enforced where every path goes
    # through it rather than at the call sites.
    test "moving a marker makes the timeline the operator's", %{conn: conn} do
      media =
        media_with_chapters([chapter(0, "One", :provider), chapter(600, "Two", :provider)],
          chapter_marker_source: :embedded
        )

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      view
      |> form("#media-chapters-form", %{
        "media" => %{
          "chapters" => %{
            "0" => %{"time" => "0", "title" => "One", "title_source" => "provider"},
            "1" => %{"time" => "612.5", "title" => "Two", "title_source" => "provider"}
          }
        }
      })
      |> render_submit()

      media = Media.get_media!(media.id)
      assert media.chapter_marker_source == :manual
      assert [_first, second] = media.chapters
      assert Decimal.equal?(second.time, Decimal.new("612.5"))
    end

    test "retitling a chapter leaves the marker source alone", %{conn: conn} do
      media =
        media_with_chapters([chapter(0, "One", :provider)], chapter_marker_source: :embedded)

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      view
      |> form("#media-chapters-form", %{
        "media" => %{
          "chapters" => %{
            "0" => %{"time" => "0", "title" => "The Dungeon Opens", "title_source" => "provider"}
          }
        }
      })
      |> render_submit()

      media = Media.get_media!(media.id)
      assert media.chapter_marker_source == :embedded
      assert [%{title: "The Dungeon Opens"}] = media.chapters
    end

    # Typing over a title is an answer, and an answer has to survive the next
    # merge — which it only does if it stops claiming a source that would let
    # the merge overwrite it.
    test "typing a title records it as the operator's", %{conn: conn} do
      media = media_with_chapters([chapter(0, "Chapter 1", :generated)])

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      view
      |> form("#media-chapters-form", %{
        "media" => %{
          "chapters" => %{
            "0" => %{"time" => "0", "title" => "Prologue", "title_source" => "generated"}
          }
        }
      })
      |> render_submit()

      assert [%{title: "Prologue", title_source: :manual}] = Media.get_media!(media.id).chapters
    end
  end

  describe "the generated floor" do
    # A generated title is a *position*, so it has to stop saying "Chapter 2"
    # the moment its row stops being the second one.
    test "renumbers generated titles when the rows move", %{conn: conn} do
      media =
        media_with_chapters([
          chapter(0, "Chapter 1", :generated),
          chapter(600, "Chapter 2", :generated)
        ])

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      html =
        view
        |> form("#media-chapters-form", %{
          "media" => %{
            "chapters" => %{
              "0" => %{"time" => "0", "title" => "Chapter 1", "title_source" => "generated"},
              "1" => %{"time" => "600", "title" => "Chapter 2", "title_source" => "generated"}
            },
            "chapters_sort" => ["1", "0"]
          }
        })
        |> render_change()

      assert [{"600", "Chapter 1"}, {"0", "Chapter 2"}] = rendered_rows(html)
    end

    test "gives a row with no title the floor rather than an error", %{conn: conn} do
      media = media_with_chapters([chapter(0, "Prologue", :manual)])

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      html =
        view
        |> form("#media-chapters-form", %{
          "media" => %{
            "chapters" => %{
              "0" => %{"time" => "0", "title" => "", "title_source" => "manual"}
            }
          }
        })
        |> render_change()

      assert [{"0", "Chapter 1"}] = rendered_rows(html)
    end

    test "leaves a title the operator chose out of the renumbering", %{conn: conn} do
      media =
        media_with_chapters([
          chapter(0, "Prologue", :manual),
          chapter(600, "Chapter 2", :generated)
        ])

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters")

      html =
        view
        |> form("#media-chapters-form", %{
          "media" => %{
            "chapters" => %{
              "0" => %{"time" => "0", "title" => "Prologue", "title_source" => "manual"},
              "1" => %{"time" => "600", "title" => "Chapter 2", "title_source" => "generated"}
            }
          }
        })
        |> render_change()

      assert html =~ ~s(value="Prologue")
      # Second row, so the floor calls it Chapter 2 — not renumbered to 1
      # just because the row above it isn't generated.
      assert html =~ ~s(value="Chapter 2")
    end
  end

  describe "re-reading the files" do
    test "offers what the files say, and applies it", %{conn: conn} do
      media = media_with_chapters([], chapter_marker_source: nil)

      {:ok, view, _html} = live(conn, ~p"/admin/media/#{media.id}/chapters?import=source")

      html = render_async(view)
      # The fixture is one plain file with no chapter marks of its own.
      assert html =~ "no chapter marks"
      refute has_element?(view, "button[phx-click='import-all']")
    end
  end
end
