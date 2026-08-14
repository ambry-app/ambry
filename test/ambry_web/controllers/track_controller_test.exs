defmodule AmbryWeb.TrackControllerTest do
  use AmbryWeb.ConnCase, async: true

  alias Ambry.Media.MediaTrack

  setup :register_and_log_in_user

  describe "GET a track" do
    test "serves the file's bytes", %{conn: conn} do
      %{track: track, contents: contents} = served_track()

      conn = get(conn, MediaTrack.web_path(track))

      assert response(conn, 200) == contents
      assert response_content_type(conn, :mp4) =~ "audio/mp4"
    end

    test "advertises range support and an etag", %{conn: conn} do
      %{track: track} = served_track()

      conn = get(conn, MediaTrack.web_path(track))

      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert [etag] = get_resp_header(conn, "etag")
      assert etag =~ ~r/^".+"$/
    end

    test "ends the URL in the file's real name, not the media id" do
      %{track: track} = served_track()

      assert MediaTrack.web_path(track) =~ ~r/\/sample\.m4a$/
    end

    test "404s for a track that doesn't exist", %{conn: conn} do
      conn = get(conn, "/files/track/#{Ambry.Hashids.encode(999_999)}/gone.m4b")

      assert response(conn, 404)
    end

    test "404s for a track whose file has vanished", %{conn: conn} do
      %{track: track, path: path} = served_track()
      File.rm!(path)

      conn = get(conn, MediaTrack.web_path(track))

      assert response(conn, 404)
    end

    test "requires authentication" do
      %{track: track} = served_track()

      conn = get(build_conn(), MediaTrack.web_path(track))

      assert response(conn, 401)
    end
  end

  describe "GET a track with a range" do
    test "serves the requested bytes as partial content", %{conn: conn} do
      %{track: track, contents: contents} = served_track()

      conn = conn |> put_req_header("range", "bytes=10-19") |> get(MediaTrack.web_path(track))

      assert response(conn, 206) == binary_part(contents, 10, 10)

      assert get_resp_header(conn, "content-range") == [
               "bytes 10-19/#{byte_size(contents)}"
             ]
    end

    test "serves an open-ended range to the end of the file", %{conn: conn} do
      %{track: track, contents: contents} = served_track()
      size = byte_size(contents)

      conn = conn |> put_req_header("range", "bytes=10-") |> get(MediaTrack.web_path(track))

      assert response(conn, 206) == binary_part(contents, 10, size - 10)
      assert get_resp_header(conn, "content-range") == ["bytes 10-#{size - 1}/#{size}"]
    end

    test "serves a suffix range from the end of the file", %{conn: conn} do
      %{track: track, contents: contents} = served_track()
      size = byte_size(contents)

      conn = conn |> put_req_header("range", "bytes=-100") |> get(MediaTrack.web_path(track))

      assert response(conn, 206) == binary_part(contents, size - 100, 100)
      assert get_resp_header(conn, "content-range") == ["bytes #{size - 100}-#{size - 1}/#{size}"]
    end

    test "clamps a range that runs past the end", %{conn: conn} do
      %{track: track, contents: contents} = served_track()
      size = byte_size(contents)

      conn =
        conn
        |> put_req_header("range", "bytes=10-999999999")
        |> get(MediaTrack.web_path(track))

      assert response(conn, 206) == binary_part(contents, 10, size - 10)
      assert get_resp_header(conn, "content-range") == ["bytes 10-#{size - 1}/#{size}"]
    end

    test "rejects a range that starts past the end", %{conn: conn} do
      %{track: track, contents: contents} = served_track()

      conn =
        conn
        |> put_req_header("range", "bytes=999999999-")
        |> get(MediaTrack.web_path(track))

      assert response(conn, 416)
      assert get_resp_header(conn, "content-range") == ["bytes */#{byte_size(contents)}"]
    end

    test "ignores an unparseable range and serves the whole file", %{conn: conn} do
      %{track: track, contents: contents} = served_track()

      conn =
        conn |> put_req_header("range", "bytes=abc-def") |> get(MediaTrack.web_path(track))

      assert response(conn, 200) == contents
    end
  end

  describe "GET a track a client already has" do
    test "answers a matching etag with 304", %{conn: conn} do
      %{track: track} = served_track()

      [etag] = conn |> get(MediaTrack.web_path(track)) |> get_resp_header("etag")

      conn =
        build_conn()
        |> log_in_user(insert(:user))
        |> put_req_header("if-none-match", etag)
        |> get(MediaTrack.web_path(track))

      assert response(conn, 304) == ""
    end

    # Replacing a recording overwrites its files in place; a changed mtime has
    # to invalidate the cached copy, or clients keep playing the old bytes.
    test "changes the etag when the file is replaced in place", %{conn: conn} do
      %{track: track, path: path} = served_track()

      [before_etag] = conn |> get(MediaTrack.web_path(track)) |> get_resp_header("etag")

      File.write!(path, "completely different contents")
      File.touch!(path, System.os_time(:second) + 10)

      [after_etag] =
        build_conn()
        |> log_in_user(insert(:user))
        |> get(MediaTrack.web_path(track))
        |> get_resp_header("etag")

      refute before_etag == after_etag
    end
  end

  defp served_track do
    media = :media |> build(book: build(:book)) |> with_copied_source_files(:m4a) |> insert()
    [source_file] = Ambry.Media.Media.source_file_paths(media)

    # the real fixture, under the media's own source folder, named as a
    # client would see it
    path = Path.join(Path.dirname(source_file), "sample.m4a")
    File.rename!(source_file, path)

    track =
      insert(:media_track, media: media, path: Ambry.Paths.disk_to_web(path), mime: "audio/mp4")

    %{track: track, path: path, contents: File.read!(path)}
  end
end
