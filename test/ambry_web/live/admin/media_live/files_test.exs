defmodule AmbryWeb.Admin.MediaLive.FilesTest do
  @moduledoc """
  What the Audio section of the edit form says a recording is made of.

  Two eras, two answers: an imported recording is its tracks, and a
  transcoded one is its packaged artifacts plus the sources they were made
  from. Asking one of them the other's question is what put a recording's
  own tracks behind a "Streaming files" fold.
  """
  use AmbryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ambry.Media

  setup :register_and_log_in_admin_user

  test "an imported recording lists the tracks it is served from", %{conn: conn} do
    media = imported_media()

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    assert html |> Floki.parse_document!() |> Floki.find("#audio li") |> Floki.text() =~
             "The Way of Kings.m4b"
  end

  test "an imported recording has no streaming files to fold away", %{conn: conn} do
    media = imported_media()

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    refute html =~ "Streaming files"
  end

  test "a transcoded recording still shows what it streams from", %{conn: conn} do
    media =
      insert(:media,
        book: build(:book),
        status: :ready,
        mp4_path: "/uploads/media/#{Ecto.UUID.generate()}.mp4",
        mpd_path: "/uploads/media/#{Ecto.UUID.generate()}.mpd",
        hls_path: "/uploads/media/#{Ecto.UUID.generate()}.m3u8"
      )

    {:ok, _view, html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    assert html =~ "Streaming files"
  end

  # An import's shape: tracks, and neither of the transcode columns.
  defp imported_media do
    media = insert(:media, book: build(:book), status: :ready)

    insert(:media_track,
      media: media,
      index: 0,
      path: "/uploads/source_media/#{Ecto.UUID.generate()}/The Way of Kings.m4b"
    )

    {:ok, media} =
      media.id
      |> Media.get_media!()
      |> Media.update_media(%{source_path: nil, source_files: []})

    media
  end
end
