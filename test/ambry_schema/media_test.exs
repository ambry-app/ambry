defmodule AmbrySchema.MediaTest do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2, from_global_id: 2]
  import Ambry.GraphQLSigil

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
            id
            title
            startTime
            endTime
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
      media = insert(:media, status: :ready)
      insert(:player_state, user_id: user.id, media: media, status: :in_progress)

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

      duration_match = Decimal.to_float(duration)

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
                     %{
                       "id" => "gY",
                       "startTime" => 0.0,
                       "endTime" => _,
                       "title" => "Chapter 1"
                     }
                     | _
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
      media = insert(:media, status: :ready)
      player_state = insert(:player_state, user_id: user.id, media: media, status: :in_progress)

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

      playback_rate_match = Decimal.to_float(playback_rate)
      position_match = Decimal.to_float(position)
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

  describe "loadPlayerState mutation" do
    @mutation ~G"""
    mutation LoadPlayerState($input: LoadPlayerStateInput!) {
      loadPlayerState(input: $input) {
        playerState {
          id
          media {
            id
          }
        }
      }
    }
    """
    test "creates a new player state when one doesn't yet exist for the given media", %{
      conn: conn
    } do
      media = insert(:media, status: :ready)
      media_gid = to_global_id("Media", media.id)

      assert %{player_states: []} = Ambry.Repo.preload(media, [:player_states])

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{input: %{media_id: media_gid}}
        })

      assert %{
               "data" => %{
                 "loadPlayerState" => %{
                   "playerState" => %{"id" => player_state_gid, "media" => %{"id" => ^media_gid}}
                 }
               }
             } = json_response(conn, 200)

      {:ok, %{id: player_state_id_string}} = from_global_id(player_state_gid, AmbrySchema)
      player_state_id = String.to_integer(player_state_id_string)

      assert %{player_states: [%{id: ^player_state_id}]} = Ambry.Repo.preload(media, [:player_states])
    end

    test "returns the existing player state for the given media", %{
      conn: conn,
      user: user
    } do
      media = insert(:media, status: :ready)
      player_state = insert(:player_state, user_id: user.id, media: media, status: :in_progress)
      media_gid = to_global_id("Media", media.id)
      player_state_gid = to_global_id("PlayerState", player_state.id)

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{input: %{media_id: media_gid}}
        })

      assert %{
               "data" => %{
                 "loadPlayerState" => %{
                   "playerState" => %{"id" => ^player_state_gid, "media" => %{"id" => ^media_gid}}
                 }
               }
             } = json_response(conn, 200)
    end
  end

  describe "updatePlayerState mutation" do
    @mutation ~G"""
    mutation UpdatePlayerState($input: UpdatePlayerStateInput!) {
      updatePlayerState(input: $input) {
        playerState {
          id
          position
          playbackRate
          media {
            id
          }
        }
      }
    }
    """
    test "creates a new player state when one doesn't yet exist for the given media", %{
      conn: conn
    } do
      media = insert(:media, status: :ready)
      media_gid = to_global_id("Media", media.id)

      assert %{player_states: []} = Ambry.Repo.preload(media, [:player_states])

      position = 123.45
      playback_rate = 1.65

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{
            input: %{media_id: media_gid, position: position, playback_rate: playback_rate}
          }
        })

      assert %{
               "data" => %{
                 "updatePlayerState" => %{
                   "playerState" => %{
                     "id" => player_state_gid,
                     "position" => ^position,
                     "playbackRate" => ^playback_rate,
                     "media" => %{"id" => ^media_gid}
                   }
                 }
               }
             } = json_response(conn, 200)

      {:ok, %{id: player_state_id_string}} = from_global_id(player_state_gid, AmbrySchema)
      player_state_id = String.to_integer(player_state_id_string)

      assert %{player_states: [%{id: ^player_state_id}]} = Ambry.Repo.preload(media, [:player_states])
    end

    test "updates the existing player state for the given media", %{
      conn: conn,
      user: user
    } do
      media = insert(:media, status: :ready)
      player_state = insert(:player_state, user_id: user.id, media: media, status: :in_progress)
      media_gid = to_global_id("Media", media.id)
      player_state_gid = to_global_id("PlayerState", player_state.id)

      position = 123.45
      playback_rate = 1.65

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{
            input: %{media_id: media_gid, position: position, playback_rate: playback_rate}
          }
        })

      assert %{
               "data" => %{
                 "updatePlayerState" => %{
                   "playerState" => %{
                     "id" => ^player_state_gid,
                     "position" => ^position,
                     "playbackRate" => ^playback_rate,
                     "media" => %{"id" => ^media_gid}
                   }
                 }
               }
             } = json_response(conn, 200)
    end
  end
end
