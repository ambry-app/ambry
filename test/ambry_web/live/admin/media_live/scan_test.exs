defmodule AmbryWeb.Admin.MediaLive.ScanTest do
  use AmbryWeb.ConnCase, async: true
  use Oban.Testing, repo: Ambry.Repo

  import Phoenix.LiveViewTest

  alias Ambry.Media
  alias Ambry.Media.RunScan

  setup :register_and_log_in_admin_user

  test "an admin can scan a media's files from the index", %{conn: conn} do
    media =
      :media
      |> build(book: build(:book, title: "The Hobbit"))
      |> with_copied_source_files(:m4a)
      |> insert()

    {:ok, view, _html} = live(conn, ~p"/admin/media")

    html = view |> element("span[phx-click='scan'][phx-value-id='#{media.id}']") |> render_click()

    assert html =~ "Scanning files for The Hobbit"
    assert_enqueued worker: RunScan, args: %{media_id: media.id}
  end

  test "the job records tracks without publishing", %{conn: conn} do
    media =
      :media
      |> build(book: build(:book))
      |> with_copied_source_files(:m4a)
      |> insert()

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    view |> element("span[phx-click='scan'][phx-value-id='#{media.id}']") |> render_click()

    assert {:ok, _media} = perform_job(RunScan, %{"media_id" => media.id})

    media = Media.get_media!(media.id)
    assert [_track] = media.media_tracks
    assert media.status == :pending
  end
end
