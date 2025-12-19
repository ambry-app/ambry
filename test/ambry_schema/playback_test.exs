defmodule AmbrySchema.PlaybackTest do
  use AmbryWeb.ConnCase

  import Ambry.GraphQLSigil
  import Ecto.Query

  alias Ambry.Playback.Device
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Repo

  setup :register_and_put_user_api_token

  describe "mutation syncProgress" do
    @mutation ~G"""
    mutation SyncProgress($input: SyncProgressInput!) {
      syncProgress(input: $input) {
        playthroughs {
          id
          status
          startedAt
          finishedAt
          abandonedAt
          deletedAt
        }
        events {
          id
          type
          timestamp
          position
          playbackRate
        }
        serverTime
      }
    }
    """

    test "syncs playthroughs and events from client", %{conn: conn, user: user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      event_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "IOS"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "IN_PROGRESS",
              "startedAt" => now
            }
          ],
          "events" => [
            %{
              "id" => event_id,
              "playthroughId" => playthrough_id,
              "type" => "PLAY",
              "timestamp" => now,
              "position" => 0.0,
              "playbackRate" => 1.0
            }
          ]
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{
               "data" => %{
                 "syncProgress" => %{
                   "playthroughs" => [
                     %{
                       "id" => ^playthrough_id,
                       "status" => "IN_PROGRESS",
                       "startedAt" => ^now,
                       "finishedAt" => nil,
                       "abandonedAt" => nil,
                       "deletedAt" => nil
                     }
                   ],
                   "events" => [
                     %{
                       "id" => ^event_id,
                       "type" => "PLAY",
                       "timestamp" => ^now,
                       "position" => +0.0,
                       "playbackRate" => +1.0
                     }
                   ],
                   "serverTime" => _server_time
                 }
               }
             } = json_response(conn, 200)

      # Verify playthrough was created
      playthrough = Repo.get!(Playthrough, playthrough_id)
      assert playthrough.user_id == user.id
      assert playthrough.media_id == media.id
      assert playthrough.status == :in_progress

      # Verify event was created
      events = Repo.all(from e in PlaybackEvent, where: e.playthrough_id == ^playthrough_id)
      assert length(events) == 1
      assert hd(events).type == :play
    end

    test "syncs resume lifecycle event", %{conn: conn, user: _user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      event_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "IOS"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "IN_PROGRESS",
              "startedAt" => now
            }
          ],
          "events" => [
            %{
              "id" => event_id,
              "playthroughId" => playthrough_id,
              "type" => "RESUME",
              "timestamp" => now
            }
          ]
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{
               "data" => %{
                 "syncProgress" => %{
                   "serverTime" => _server_time
                 }
               }
             } = json_response(conn, 200)

      # Verify resume event was created without position/playbackRate
      events = Repo.all(from e in PlaybackEvent, where: e.playthrough_id == ^playthrough_id)
      assert length(events) == 1
      resume_event = hd(events)
      assert resume_event.type == :resume
      assert resume_event.position == nil
      assert resume_event.playback_rate == nil
    end

    test "returns server changes since lastSyncTime", %{conn: conn, user: user} do
      # Create existing playthrough and event on server
      media = insert(:media, book: build(:book))
      playthrough = insert(:playthrough, user: user, media: media)

      old_event =
        insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 10:00:00Z])

      # Sync with a recent lastSyncTime
      device_id = Ecto.UUID.generate()
      last_sync = ~U[2025-01-01 09:00:00Z] |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => last_sync,
          "device" => %{
            "id" => device_id,
            "type" => "ANDROID"
          },
          "playthroughs" => [],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      response = json_response(conn, 200)

      assert %{
               "data" => %{
                 "syncProgress" => %{
                   "playthroughs" => playthroughs,
                   "events" => events,
                   "serverTime" => _server_time
                 }
               }
             } = response

      # Should return the playthrough since it was created after lastSyncTime
      assert length(playthroughs) == 1
      assert hd(playthroughs)["id"] == playthrough.id

      # Should return the event since it was created after lastSyncTime
      assert length(events) == 1
      assert hd(events)["id"] == old_event.id
    end

    test "registers device on sync", %{conn: conn, user: user} do
      device_id = Ecto.UUID.generate()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "IOS",
            "brand" => "Apple",
            "modelName" => "iPhone 14 Pro",
            "osName" => "iOS",
            "osVersion" => "17.0"
          },
          "playthroughs" => [],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{"data" => %{"syncProgress" => _}} = json_response(conn, 200)

      # Verify device was registered
      device = Repo.get!(Device, device_id)
      assert device.user_id == user.id
      assert device.type == :ios
      assert device.brand == "Apple"
      assert device.model_name == "iPhone 14 Pro"
    end

    test "handles finished playthrough sync", %{conn: conn, user: _user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "IOS"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "FINISHED",
              "startedAt" => now,
              "finishedAt" => now
            }
          ],
          "events" => [
            %{
              "id" => Ecto.UUID.generate(),
              "playthroughId" => playthrough_id,
              "type" => "FINISH",
              "timestamp" => now
            }
          ]
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{"data" => %{"syncProgress" => _}} = json_response(conn, 200)

      # Verify finished playthrough
      playthrough = Repo.get!(Playthrough, playthrough_id)
      assert playthrough.status == :finished
      assert playthrough.finished_at != nil
    end

    test "handles abandoned playthrough sync", %{conn: conn, user: _user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "ANDROID"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "ABANDONED",
              "startedAt" => now,
              "abandonedAt" => now
            }
          ],
          "events" => [
            %{
              "id" => Ecto.UUID.generate(),
              "playthroughId" => playthrough_id,
              "type" => "ABANDON",
              "timestamp" => now
            }
          ]
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{"data" => %{"syncProgress" => _}} = json_response(conn, 200)

      # Verify abandoned playthrough
      playthrough = Repo.get!(Playthrough, playthrough_id)
      assert playthrough.status == :abandoned
      assert playthrough.abandoned_at != nil
    end

    test "handles seek event with from/to positions", %{conn: conn, user: _user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      event_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "ANDROID"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "IN_PROGRESS",
              "startedAt" => now
            }
          ],
          "events" => [
            %{
              "id" => event_id,
              "playthroughId" => playthrough_id,
              "type" => "SEEK",
              "timestamp" => now,
              "position" => 500.0,
              "playbackRate" => 1.5,
              "fromPosition" => 100.0,
              "toPosition" => 500.0
            }
          ]
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{"data" => %{"syncProgress" => _}} = json_response(conn, 200)

      # Verify seek event with from/to positions
      events = Repo.all(from e in PlaybackEvent, where: e.playthrough_id == ^playthrough_id)
      assert length(events) == 1
      seek_event = hd(events)
      assert seek_event.type == :seek
      assert Decimal.eq?(seek_event.from_position, Decimal.new("100.0"))
      assert Decimal.eq?(seek_event.to_position, Decimal.new("500.0"))
    end

    test "can receive events from web devices in sync response", %{conn: conn, user: user} do
      # Create a web device and playthrough server-side (simulating web UI activity)
      media = insert(:media, book: build(:book))
      web_device = insert(:device, user: user, type: :web)
      playthrough = insert(:playthrough, user: user, media: media)
      _web_event = insert(:playback_event, playthrough: playthrough, device: web_device)

      # Mobile client syncs - should receive events from web device
      last_sync = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => last_sync,
          "device" => %{
            "id" => Ecto.UUID.generate(),
            "type" => "IOS"
          },
          "playthroughs" => [],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      response = json_response(conn, 200)

      # Should successfully receive playthroughs and events from web device
      assert %{
               "data" => %{
                 "syncProgress" => %{
                   "playthroughs" => _playthroughs,
                   "events" => _events
                 }
               }
             } = response
    end

    test "rejects web devices at GraphQL schema level", %{conn: conn} do
      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => Ecto.UUID.generate(),
            "type" => "WEB"
          },
          "playthroughs" => [],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      response = json_response(conn, 200)

      # GraphQL schema validation rejects WEB (not in device_type_input enum)
      assert %{"errors" => [error | _]} = response
      assert error["message"] =~ ~r/Expected type "DeviceTypeInput!"/
      assert error["message"] =~ ~r/found "WEB"/
    end

    test "returns unauthorized error without api token", %{conn: conn} do
      conn = remove_user_api_token(conn)

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{"id" => Ecto.UUID.generate(), "type" => "IOS"},
          "playthroughs" => [],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{
               "data" => %{"syncProgress" => nil},
               "errors" => [
                 %{
                   "message" => "unauthorized",
                   "path" => ["syncProgress"]
                 }
               ]
             } = json_response(conn, 200)
    end

    test "handles soft-deleted playthrough", %{conn: conn, user: _user} do
      media = insert(:media, book: build(:book))
      playthrough_id = Ecto.UUID.generate()
      device_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      variables = %{
        "input" => %{
          "lastSyncTime" => nil,
          "device" => %{
            "id" => device_id,
            "type" => "IOS"
          },
          "playthroughs" => [
            %{
              "id" => playthrough_id,
              "mediaId" => Absinthe.Relay.Node.to_global_id(:media, media.id, AmbrySchema),
              "status" => "IN_PROGRESS",
              "startedAt" => now,
              "deletedAt" => now
            }
          ],
          "events" => []
        }
      }

      conn =
        post(conn, "/gql", %{
          "query" => @mutation,
          "variables" => variables
        })

      assert %{"data" => %{"syncProgress" => _}} = json_response(conn, 200)

      # Verify playthrough was created with deleted_at
      playthrough = Repo.get!(Playthrough, playthrough_id)
      assert playthrough.deleted_at != nil
    end
  end
end
