defmodule AmbrySchema.MediaTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil
  import Absinthe.Relay.Node, only: [to_global_id: 2]

  setup :register_and_put_user_api_token

  describe "Media node" do
    @query ~G"""
    query Media($id: ID!) {
      node(id: $id) {
        id
        ... on Media {
          fullCast
          abridged
          duration
          mpdPath
          hlsPath
          chapters {
            time
            title
          }
          book {
            __typename
          }
          narrators {
            __typename
          }
          playerState {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves Media fields", %{conn: conn, user: user} do
      %{media: media} = insert(:player_state, user_id: user.id, status: :in_progress)

      %{
        id: id,
        full_cast: full_cast,
        abridged: abridged,
        duration: duration,
        mpd_path: mpd_path,
        hls_path: hls_path
      } = media

      gid = to_global_id("Media", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      duration_match = Decimal.to_string(duration)

      assert %{
               "data" => %{
                 "node" => %{
                   "id" => ^gid,
                   "fullCast" => ^full_cast,
                   "abridged" => ^abridged,
                   "duration" => ^duration_match,
                   "mpdPath" => ^mpd_path,
                   "hlsPath" => ^hls_path,
                   "chapters" => [
                     %{"time" => "0", "title" => "Chapter 1"} | _
                   ],
                   "book" => %{"__typename" => "Book"},
                   "narrators" => [%{"__typename" => "Narrator"} | _],
                   "playerState" => %{"__typename" => "PlayerState"},
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "PlayerState node" do
    @query ~G"""
    query PlayerState($id: ID!) {
      node(id: $id) {
        id
        ... on PlayerState {
          playbackRate
          position
          status
          media {
            __typename
          }
          insertedAt
          updatedAt
        }
      }
    }
    """
    test "resolves PlayerState fields", %{conn: conn, user: user} do
      player_state = insert(:player_state, user_id: user.id, status: :in_progress)

      %{
        id: id,
        playback_rate: playback_rate,
        position: position,
        status: status
      } = player_state

      gid = to_global_id("PlayerState", id)

      conn =
        post(conn, "/gql", %{
          "query" => @query,
          "variables" => %{id: gid}
        })

      playback_rate_match = Decimal.to_string(playback_rate)
      position_match = Decimal.to_string(position)
      status_match = status |> Atom.to_string() |> String.upcase()

      assert %{
               "data" => %{
                 "node" => %{
                   "playbackRate" => ^playback_rate_match,
                   "position" => ^position_match,
                   "status" => ^status_match,
                   "media" => %{"__typename" => "Media"},
                   "insertedAt" => "" <> _,
                   "updatedAt" => "" <> _
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "playerStates connection" do
    @query ~G"""
    query PlayerStates {
      playerStates(first: 1) {
        __typename
      }
    }
    """
    test "returns an unauthorized error if missing api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      conn =
        post(conn, "/gql", %{
          "query" => @query
        })

      assert %{
               "data" => %{"playerStates" => nil},
               "errors" => [
                 %{
                   "locations" => [%{"column" => 3, "line" => 2}],
                   "message" => "unauthorized",
                   "path" => ["playerStates"]
                 }
               ]
             } = json_response(conn, 200)
    end

    test "resolves the playerStates connection", %{conn: conn} do
      conn =
        post(conn, "/gql", %{
          "query" => @query
        })

      assert %{
               "data" => %{
                 "playerStates" => %{"__typename" => "PlayerStateConnection"}
               }
             } = json_response(conn, 200)
    end
  end
end
