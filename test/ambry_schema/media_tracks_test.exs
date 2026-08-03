defmodule AmbrySchema.MediaTracksTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.GraphQLSigil

  alias Ambry.Media
  alias Ambry.Media.MediaTrack

  setup :register_and_put_user_api_token

  describe "Media.tracks" do
    @query ~G"""
    query Media($id: ID!) {
      node(id: $id) {
        ... on Media {
          duration
          tracks {
            id
            index
            path
            size
            mime
            format
            codec
            duration
            startOffset
            seekAccuracy
          }
        }
      }
    }
    """
    test "resolves a recording's tracks", %{conn: conn} do
      media = insert(:media, book: build(:book))

      track =
        insert(:media_track,
          media: media,
          index: 0,
          size: 123_456,
          mime: "audio/mp4",
          format: "mov,mp4,m4a,3gp,3g2,mj2",
          codec: "aac",
          duration: Decimal.new("3600.5"),
          start_offset: Decimal.new(0),
          seek_accuracy: :exact
        )

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{id: gid(media)}})

      assert %{
               "data" => %{
                 "node" => %{
                   "tracks" => [
                     %{
                       "index" => 0,
                       "path" => path,
                       "size" => size,
                       "mime" => "audio/mp4",
                       "format" => "mov,mp4,m4a,3gp,3g2,mj2",
                       "codec" => "aac",
                       "duration" => track_duration,
                       "startOffset" => start_offset,
                       "seekAccuracy" => "EXACT"
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)

      assert path == MediaTrack.web_path(track)
      assert size == 123_456.0
      assert track_duration == 3600.5
      assert start_offset == 0.0
    end

    test "orders them by their place on the timeline", %{conn: conn} do
      media = insert(:media, book: build(:book))
      insert(:media_track, media: media, index: 1, start_offset: Decimal.new("3600"))
      insert(:media_track, media: media, index: 0, start_offset: Decimal.new(0))

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{id: gid(media)}})

      assert %{"data" => %{"node" => %{"tracks" => [%{"index" => 0}, %{"index" => 1}]}}} =
               json_response(conn, 200)
    end

    test "is empty for a legacy recording rather than absent", %{conn: conn} do
      media = insert(:media, book: build(:book))

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{id: gid(media)}})

      assert %{"data" => %{"node" => %{"tracks" => []}}} = json_response(conn, 200)
    end

    test "reports a size no 32-bit Int could carry", %{conn: conn} do
      media = insert(:media, book: build(:book))
      insert(:media_track, media: media, size: 5_000_000_000)

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{id: gid(media)}})

      assert %{"data" => %{"node" => %{"tracks" => [%{"size" => size}]}}} =
               json_response(conn, 200)

      assert size == 5_000_000_000.0
    end
  end

  describe "mediaTracksChangedSince" do
    @query ~G"""
    query Sync($since: DateTime) {
      mediaTracksChangedSince(since: $since) {
        id
        index
        path
        media {
          id
        }
      }
      deletionsSince(since: $since) {
        type
        recordId
      }
    }
    """
    test "returns tracks and records their deletions", %{conn: conn} do
      media = insert(:media, book: build(:book))
      track = insert(:media_track, media: media, index: 0)

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{}})

      assert %{
               "data" => %{
                 "mediaTracksChangedSince" => [%{"index" => 0, "media" => %{"id" => media_gid}}],
                 "deletionsSince" => []
               }
             } = json_response(conn, 200)

      assert media_gid == gid(media)

      {:ok, _track} = Ambry.Repo.delete(track)

      # deletions are only reported against a `since` — a client with no
      # previous sync gets the current world, not its history
      since = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()
      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{since: since}})

      assert %{
               "data" => %{
                 "mediaTracksChangedSince" => [],
                 "deletionsSince" => [%{"type" => "MEDIA_TRACK", "recordId" => deleted_gid}]
               }
             } = json_response(conn, 200)

      assert deleted_gid == to_global_id("MediaTrack", track.id)
    end

    test "reports tracks of media a client can't see yet, harmlessly", %{conn: conn} do
      # a scanned-but-unpublished media syncs its tracks; clients only ever
      # play `ready` media, so this costs a few rows and no correctness
      media = insert(:media, book: build(:book), status: :pending)
      insert(:media_track, media: media)

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{}})

      assert %{"data" => %{"mediaTracksChangedSince" => [_track]}} = json_response(conn, 200)
    end
  end

  describe "a scanned recording end to end" do
    @query ~G"""
    query Media($id: ID!) {
      node(id: $id) {
        ... on Media {
          duration
          tracks {
            path
            mime
            codec
            seekAccuracy
          }
        }
      }
    }
    """
    test "is playable straight from what the scanner wrote", %{conn: conn} do
      media =
        :media
        |> build(book: build(:book))
        |> with_copied_source_files(:m4a)
        |> insert()
        |> then(&Media.get_media!(&1.id))

      {:ok, media} = Media.scan_media(media)

      conn = post(conn, "/gql", %{"query" => @query, "variables" => %{id: gid(media)}})

      assert %{
               "data" => %{
                 "node" => %{
                   "duration" => duration,
                   "tracks" => [
                     %{
                       "path" => "/files/track/" <> _,
                       "mime" => "audio/mp4",
                       "codec" => "aac",
                       "seekAccuracy" => "EXACT"
                     }
                   ]
                 }
               }
             } = json_response(conn, 200)

      assert duration > 3.8 and duration < 3.9
    end
  end

  defp gid(%{id: id}), do: to_global_id("Media", id)
end
