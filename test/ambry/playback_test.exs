defmodule Ambry.PlaybackTest do
  use Ambry.DataCase

  alias Ambry.Playback

  describe "register_device/1" do
    test "registers a new device" do
      user = insert(:user)

      attrs = %{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        type: :ios,
        brand: "Apple",
        model_name: "iPhone 14",
        os_name: "iOS",
        os_version: "16.0"
      }

      assert {:ok, device} = Playback.register_device(attrs)
      assert device.id == attrs.id
      assert device.type == :ios
      assert device.brand == "Apple"
    end

    test "updates last_seen_at on duplicate device" do
      user = insert(:user)
      device_id = Ecto.UUID.generate()

      attrs = %{
        id: device_id,
        user_id: user.id,
        type: :web
      }

      {:ok, device1} = Playback.register_device(attrs)
      :timer.sleep(1000)
      {:ok, device2} = Playback.register_device(attrs)

      assert device1.id == device2.id
      assert DateTime.after?(device2.last_seen_at, device1.last_seen_at)
    end
  end

  describe "fetch_device/1" do
    test "returns {:ok, device} when device exists" do
      device = insert(:device)

      assert {:ok, fetched} = Playback.fetch_device(device.id)
      assert fetched.id == device.id
    end

    test "returns {:error, :not_found} when device doesn't exist" do
      assert {:error, :not_found} = Playback.fetch_device(Ecto.UUID.generate())
    end
  end

  describe "list_devices/1" do
    test "returns all devices for a user ordered by last_seen_at" do
      user = insert(:user)
      device1 = insert(:device, user: user, last_seen_at: ~U[2025-01-01 10:00:00Z])
      device2 = insert(:device, user: user, last_seen_at: ~U[2025-01-02 10:00:00Z])
      _other_device = insert(:device)

      devices = Playback.list_devices(user.id)

      assert length(devices) == 2
      assert hd(devices).id == device2.id
      assert List.last(devices).id == device1.id
    end
  end

  describe "upsert_playthrough/1" do
    test "creates a new playthrough" do
      user = insert(:user)
      media = insert(:media, book: build(:book))

      attrs = %{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        media_id: media.id,
        status: :in_progress,
        started_at: DateTime.utc_now()
      }

      assert {:ok, playthrough} = Playback.upsert_playthrough(attrs)
      assert playthrough.status == :in_progress
      assert playthrough.user_id == user.id
    end

    test "updates an existing playthrough" do
      playthrough = insert(:playthrough, status: :in_progress)

      attrs = %{
        id: playthrough.id,
        user_id: playthrough.user_id,
        media_id: playthrough.media_id,
        status: :finished,
        started_at: playthrough.started_at,
        finished_at: DateTime.utc_now()
      }

      assert {:ok, updated} = Playback.upsert_playthrough(attrs)
      assert updated.id == playthrough.id
      assert updated.status == :finished
      assert updated.finished_at != nil
    end
  end

  describe "get_active_playthrough/2" do
    test "returns the active playthrough for user and media" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      playthrough = insert(:playthrough, user: user, media: media, status: :in_progress)

      assert fetched = Playback.get_active_playthrough(user.id, media.id)
      assert fetched.id == playthrough.id
    end

    test "returns nil when no active playthrough exists" do
      user = insert(:user)
      media = insert(:media, book: build(:book))
      _finished = insert(:finished_playthrough, user: user, media: media)

      assert Playback.get_active_playthrough(user.id, media.id) == nil
    end
  end

  describe "fetch_playthrough/1" do
    test "returns {:ok, playthrough} when playthrough exists" do
      playthrough = insert(:playthrough)

      assert {:ok, fetched} = Playback.fetch_playthrough(playthrough.id)
      assert fetched.id == playthrough.id
    end

    test "returns {:error, :not_found} when playthrough doesn't exist" do
      assert {:error, :not_found} = Playback.fetch_playthrough(Ecto.UUID.generate())
    end
  end

  describe "get_playthrough!/1" do
    test "returns playthrough when it exists" do
      playthrough = insert(:playthrough)

      assert fetched = Playback.get_playthrough!(playthrough.id)
      assert fetched.id == playthrough.id
    end

    test "raises when playthrough doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Playback.get_playthrough!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_playthroughs/2" do
    test "returns playthroughs for a user ordered by updated_at" do
      user = insert(:user)
      p1 = insert(:playthrough, user: user, updated_at: ~U[2025-01-01 10:00:00Z])
      p2 = insert(:playthrough, user: user, updated_at: ~U[2025-01-02 10:00:00Z])
      _other = insert(:playthrough)

      playthroughs = Playback.list_playthroughs(user.id)

      assert length(playthroughs) == 2
      assert hd(playthroughs).id == p2.id
      assert List.last(playthroughs).id == p1.id
    end

    test "filters by status" do
      user = insert(:user)
      _in_progress = insert(:playthrough, user: user, status: :in_progress)
      finished = insert(:finished_playthrough, user: user)

      playthroughs = Playback.list_playthroughs(user.id, status: :finished)

      assert length(playthroughs) == 1
      assert hd(playthroughs).id == finished.id
    end

    test "respects limit and offset" do
      user = insert(:user)
      insert_list(10, :playthrough, user: user)

      playthroughs = Playback.list_playthroughs(user.id, limit: 5, offset: 3)

      assert length(playthroughs) == 5
    end
  end

  describe "list_playthroughs_changed_since/2" do
    test "returns playthroughs updated after the given time" do
      user = insert(:user)
      old = insert(:playthrough, user: user, updated_at: ~U[2025-01-01 10:00:00Z])
      new = insert(:playthrough, user: user, updated_at: ~U[2025-01-02 10:00:00Z])

      since = ~U[2025-01-01 12:00:00Z]
      playthroughs = Playback.list_playthroughs_changed_since(user.id, since)

      assert length(playthroughs) == 1
      assert hd(playthroughs).id == new.id
      refute Enum.any?(playthroughs, &(&1.id == old.id))
    end
  end

  describe "finish_playthrough/1" do
    test "marks playthrough as finished" do
      playthrough = insert(:playthrough, status: :in_progress)

      assert {:ok, finished} = Playback.finish_playthrough(playthrough)
      assert finished.status == :finished
      assert finished.finished_at != nil
    end
  end

  describe "abandon_playthrough/1" do
    test "marks playthrough as abandoned" do
      playthrough = insert(:playthrough, status: :in_progress)

      assert {:ok, abandoned} = Playback.abandon_playthrough(playthrough)
      assert abandoned.status == :abandoned
      assert abandoned.abandoned_at != nil
    end
  end

  describe "delete_playthrough/1" do
    test "soft-deletes a playthrough" do
      playthrough = insert(:playthrough)

      assert {:ok, deleted} = Playback.delete_playthrough(playthrough)
      assert deleted.deleted_at != nil
    end
  end

  describe "resume_playthrough/1" do
    test "reverts finished playthrough to in_progress" do
      playthrough = insert(:finished_playthrough)

      assert {:ok, resumed} = Playback.resume_playthrough(playthrough)
      assert resumed.status == :in_progress
      assert resumed.finished_at == nil
    end

    test "reverts abandoned playthrough to in_progress" do
      playthrough = insert(:abandoned_playthrough)

      assert {:ok, resumed} = Playback.resume_playthrough(playthrough)
      assert resumed.status == :in_progress
      assert resumed.abandoned_at == nil
    end
  end

  describe "record_event/1" do
    test "records a playback event" do
      playthrough = insert(:playthrough)

      attrs = %{
        id: Ecto.UUID.generate(),
        playthrough_id: playthrough.id,
        type: :play,
        timestamp: DateTime.utc_now(),
        position: Decimal.new("100.5"),
        playback_rate: Decimal.new("1.0")
      }

      assert {:ok, event} = Playback.record_event(attrs)
      assert event.type == :play
      assert Decimal.eq?(event.position, Decimal.new("100.5"))
    end

    test "records a lifecycle event without position/rate" do
      playthrough = insert(:playthrough)

      attrs = %{
        id: Ecto.UUID.generate(),
        playthrough_id: playthrough.id,
        type: :start,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, event} = Playback.record_event(attrs)
      assert event.type == :start
      assert event.position == nil
      assert event.playback_rate == nil
    end

    test "records resume lifecycle event" do
      playthrough = insert(:playthrough)

      attrs = %{
        id: Ecto.UUID.generate(),
        playthrough_id: playthrough.id,
        type: :resume,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, event} = Playback.record_event(attrs)
      assert event.type == :resume
      assert event.position == nil
      assert event.playback_rate == nil
    end

    test "is idempotent - duplicate id doesn't error" do
      playthrough = insert(:playthrough)
      event_id = Ecto.UUID.generate()

      attrs = %{
        id: event_id,
        playthrough_id: playthrough.id,
        type: :play,
        timestamp: DateTime.utc_now(),
        position: Decimal.new("100"),
        playback_rate: Decimal.new("1.0")
      }

      assert {:ok, _event1} = Playback.record_event(attrs)
      assert {:ok, _event2} = Playback.record_event(attrs)
    end
  end

  describe "record_events/1" do
    test "records multiple events" do
      playthrough = insert(:playthrough)

      events = [
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :play,
          timestamp: DateTime.utc_now(),
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0")
        },
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :pause,
          timestamp: DateTime.utc_now(),
          position: Decimal.new("100"),
          playback_rate: Decimal.new("1.0")
        }
      ]

      assert {:ok, 2} = Playback.record_events(events)
    end
  end

  describe "list_events/1" do
    test "returns all events for a playthrough ordered by timestamp" do
      playthrough = insert(:playthrough)
      e1 = insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 10:00:00Z])
      e2 = insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 11:00:00Z])
      _other = insert(:playback_event)

      events = Playback.list_events(playthrough.id)

      assert length(events) == 2
      assert hd(events).id == e1.id
      assert List.last(events).id == e2.id
    end
  end

  describe "get_latest_event/1" do
    test "returns the most recent event" do
      playthrough = insert(:playthrough)

      _old =
        insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 10:00:00Z])

      new = insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 11:00:00Z])

      assert latest = Playback.get_latest_event(playthrough.id)
      assert latest.id == new.id
    end

    test "returns nil when no events exist" do
      playthrough = insert(:playthrough)

      assert Playback.get_latest_event(playthrough.id) == nil
    end
  end

  describe "list_events_changed_since/2" do
    test "returns events after the given time" do
      user = insert(:user)
      playthrough = insert(:playthrough, user: user)
      old = insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-01 10:00:00Z])
      new = insert(:playback_event, playthrough: playthrough, timestamp: ~U[2025-01-02 10:00:00Z])

      since = ~U[2025-01-01 12:00:00Z]
      events = Playback.list_events_changed_since(user.id, since)

      assert length(events) == 1
      assert hd(events).id == new.id
      refute Enum.any?(events, &(&1.id == old.id))
    end
  end

  describe "derive_state/1" do
    test "derives current state from playback events" do
      playthrough = insert(:playthrough)

      insert(:playback_event,
        playthrough: playthrough,
        type: :play,
        timestamp: ~U[2025-01-01 10:00:00Z],
        position: Decimal.new("0"),
        playback_rate: Decimal.new("1.0")
      )

      insert(:playback_event,
        playthrough: playthrough,
        type: :pause,
        timestamp: ~U[2025-01-01 10:05:00Z],
        position: Decimal.new("300"),
        playback_rate: Decimal.new("1.0")
      )

      state = Playback.derive_state(playthrough.id)

      assert Decimal.eq?(state.position, Decimal.new("300"))
      assert Decimal.eq?(state.playback_rate, Decimal.new("1.0"))
      assert state.last_event_at == ~U[2025-01-01 10:05:00Z]
      assert Decimal.eq?(state.total_listening_time, Decimal.new("300"))
    end

    test "ignores lifecycle events when deriving state" do
      playthrough = insert(:playthrough)

      insert(:lifecycle_event,
        playthrough: playthrough,
        type: :start,
        timestamp: ~U[2025-01-01 09:00:00Z]
      )

      insert(:playback_event,
        playthrough: playthrough,
        type: :play,
        timestamp: ~U[2025-01-01 10:00:00Z],
        position: Decimal.new("100"),
        playback_rate: Decimal.new("1.5")
      )

      state = Playback.derive_state(playthrough.id)

      assert Decimal.eq?(state.position, Decimal.new("100"))
      assert Decimal.eq?(state.playback_rate, Decimal.new("1.5"))
      assert state.last_event_at == ~U[2025-01-01 10:00:00Z]
    end

    test "returns defaults when no playback events exist" do
      playthrough = insert(:playthrough)

      state = Playback.derive_state(playthrough.id)

      assert Decimal.eq?(state.position, Decimal.new("0"))
      assert Decimal.eq?(state.playback_rate, Decimal.new("1"))
      assert state.last_event_at == nil
      assert Decimal.eq?(state.total_listening_time, Decimal.new("0"))
    end
  end

  describe "calculate_listening_time/1" do
    test "calculates time between play and pause events" do
      events = [
        %{type: :play, position: Decimal.new("0"), playback_rate: Decimal.new("1.0")},
        %{type: :pause, position: Decimal.new("300"), playback_rate: Decimal.new("1.0")}
      ]

      time = Playback.calculate_listening_time(events)

      assert Decimal.eq?(time, Decimal.new("300"))
    end

    test "adjusts for playback rate" do
      events = [
        %{type: :play, position: Decimal.new("0"), playback_rate: Decimal.new("2.0")},
        %{type: :pause, position: Decimal.new("400"), playback_rate: Decimal.new("2.0")}
      ]

      time = Playback.calculate_listening_time(events)

      # 400 seconds at 2x speed = 200 seconds real time
      assert Decimal.eq?(time, Decimal.new("200"))
    end

    test "sums multiple play/pause segments" do
      events = [
        %{type: :play, position: Decimal.new("0"), playback_rate: Decimal.new("1.0")},
        %{type: :pause, position: Decimal.new("100"), playback_rate: Decimal.new("1.0")},
        %{type: :play, position: Decimal.new("100"), playback_rate: Decimal.new("1.0")},
        %{type: :pause, position: Decimal.new("250"), playback_rate: Decimal.new("1.0")}
      ]

      time = Playback.calculate_listening_time(events)

      assert Decimal.eq?(time, Decimal.new("250"))
    end
  end

  describe "sync_playthroughs/1" do
    test "upserts multiple playthroughs" do
      user = insert(:user)
      media = insert(:media, book: build(:book))

      playthroughs_data = [
        %{
          id: Ecto.UUID.generate(),
          user_id: user.id,
          media_id: media.id,
          status: :in_progress,
          started_at: DateTime.utc_now()
        }
      ]

      result = Playback.sync_playthroughs(playthroughs_data)

      assert length(result) == 1
      assert hd(result).status == :in_progress
    end
  end

  describe "sync_events/1" do
    test "records multiple events" do
      playthrough = insert(:playthrough)

      events_data = [
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :play,
          timestamp: DateTime.utc_now(),
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0")
        }
      ]

      assert {:ok, 1} = Playback.sync_events(events_data)
    end
  end
end
