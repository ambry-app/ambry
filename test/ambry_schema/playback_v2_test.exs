defmodule AmbrySchema.PlaybackV2Test do
  use AmbryWeb.ConnCase

  import Absinthe.Relay.Node, only: [to_global_id: 2]
  import Ambry.Factory
  import Ambry.GraphQLSigil

  setup :register_and_put_user_api_token

  describe "syncEvents mutation" do
    @mutation ~G"""
    mutation SyncEvents($input: SyncEventsInput!) {
      syncEvents(input: $input) {
        events {
          id
          mediaId
        }
        serverTime
      }
    }
    """

    test "returns events with global relay IDs for mediaId", %{conn: conn, user: _user} do
      media = insert(:media, book: insert(:book))
      device_id = Ecto.UUID.generate()

      # V2 of the sync protocol uses a UUID for the playthrough ID
      playthrough_id = Ecto.UUID.generate()

      event =
        build(:playback_event,
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough_id,
          device_id: device_id,
          media_id: media.id,
          type: :start
        )

      events_input = [
        %{
          id: event.id,
          playthroughId: event.playthrough_id,
          mediaId: to_global_id("Media", event.media_id),
          type: "START",
          timestamp: DateTime.to_iso8601(event.timestamp),
          position: 0.0,
          playbackRate: 1.0
        }
      ]

      # The sync mutation will create the device and link it to the authenticated user
      device_input = %{
        id: device_id,
        type: "IOS"
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => %{
            "input" => %{
              "device" => device_input,
              "events" => events_input,
              "lastSyncTime" => nil
            }
          }
        })

      json = json_response(conn, 200)

      expected_media_id = to_global_id("Media", media.id)

      assert %{
               "data" => %{
                 "syncEvents" => %{
                   "events" => [
                     %{
                       "id" => _event_id,
                       "mediaId" => ^expected_media_id
                     }
                   ],
                   "serverTime" => _
                 }
               }
             } = json
    end
  end
end
