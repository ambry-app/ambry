defmodule AmbryWeb.Admin.MediaLive.FileChaptersTest do
  @moduledoc """
  Reading a recording's chapter markers back off its files.

  Markers are file-derived facts, and the inbox has always been able to say
  "take what the probe read". The edit form could not: a recording whose rows
  were wrong had no way back to the files short of re-importing it
  (`EDIT_PARITY_PLAN.md` phase 4).
  """
  use AmbryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ambry.Media
  alias Ambry.Media.Media.Chapter

  setup :register_and_log_in_admin_user

  defp media_with(file_count, chapters) do
    :media
    |> build(book: build(:book), chapters: chapters)
    |> with_copied_source_files(:m4a, file_count)
    |> insert()
  end

  defp typed_rows do
    [
      %Chapter{time: Decimal.new(0), title: "Something typed", title_source: :manual}
    ]
  end

  defp take_files(view) do
    view |> element("button[phx-click='take-file-chapters']") |> render_click()
    render_async(view)
  end

  test "the files' chip replaces the rows and moves the source line with them",
       %{conn: conn} do
    media = media_with(2, typed_rows())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html = take_files(view)

    # two files, no embedded markers: one marker per file boundary
    assert html =~ "Read 2 chapters from the files"
    assert html =~ "file_boundaries"

    view |> form("#media-form", %{"media" => %{}}) |> render_submit()

    media = Media.get_media!(media.id)
    assert length(media.chapters) == 2
    assert media.chapter_marker_source == :file_boundaries
    refute Enum.any?(media.chapters, &(&1.title == "Something typed"))
  end

  # A chip that emptied rows the operator typed by hand would be a
  # destructive control wearing a proposal's clothes — the rule the inbox's
  # own chip follows.
  test "files that carry no markers leave the rows alone", %{conn: conn} do
    media = media_with(1, typed_rows())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    html = take_files(view)

    assert html =~ "carry no chapter markers"
    assert html =~ "Something typed"

    media = Media.get_media!(media.id)
    assert [%Chapter{title: "Something typed"}] = media.chapters
  end

  # Nothing is written until Save, here as everywhere else on this form.
  test "re-reading saves nothing on its own", %{conn: conn} do
    media = media_with(2, typed_rows())

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")
    take_files(view)

    assert [%Chapter{title: "Something typed"}] = Media.get_media!(media.id).chapters
  end
end
