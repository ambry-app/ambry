defmodule AmbryWeb.Admin.MediaLive.FilesTest do
  @moduledoc """
  What the Audio section of the edit form says a recording is made of.

  Two kinds of recording, two answers: an imported one is its tracks, and a
  transcoded one is its packaged artifacts plus the sources they were made
  from. Neither may be shown the other's.
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

  test "the files say which library root they are in", %{conn: conn} do
    media = imported_media(root: insert(:root, name: "Audiobooks"))

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    assert has_element?(view, "[data-role='files-header'] [data-role='place']", "Audiobooks")
  end

  # A track can sit outside every root, and a badge that named one anyway
  # would state a fact the database does not hold.
  test "a recording outside every root names none", %{conn: conn} do
    media = imported_media()

    {:ok, view, _html} = live(conn, ~p"/admin/audiobooks/#{media}/edit")

    assert has_element?(view, "[data-role='files-header']")
    refute has_element?(view, "[data-role='files-header'] [data-role='place']")
  end

  # An import's shape: tracks, and neither of the transcode columns.
  defp imported_media(opts \\ []) do
    media = insert(:media, book: build(:book), status: :ready)
    root = Keyword.get(opts, :root)

    # `media_tracks_path_resolvable`: a path under a root is relative to it,
    # and a path with no root is an absolute one under uploads.
    path =
      if root,
        do: "Sanderson/The Way of Kings/The Way of Kings.m4b",
        else: "/uploads/source_media/#{Ecto.UUID.generate()}/The Way of Kings.m4b"

    insert(:media_track, media: media, index: 0, library_root: root, path: path)

    {:ok, media} =
      media.id
      |> Media.get_media!()
      |> Media.update_media(%{source_path: nil, source_files: []})

    media
  end
end
