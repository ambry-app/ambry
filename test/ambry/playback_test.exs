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
      link1 = Ambry.Repo.get_by!(Playback.DeviceUser, device_id: device_id, user_id: user.id)

      :timer.sleep(1000)
      {:ok, device2} = Playback.register_device(attrs)
      link2 = Ambry.Repo.get_by!(Playback.DeviceUser, device_id: device_id, user_id: user.id)

      assert device1.id == device2.id
      assert DateTime.after?(link2.last_seen_at, link1.last_seen_at)
    end

    test "allows the same device to be used by multiple users" do
      user1 = insert(:user)
      user2 = insert(:user)
      device_id = Ecto.UUID.generate()

      attrs1 = %{id: device_id, user_id: user1.id, type: :ios}
      attrs2 = %{id: device_id, user_id: user2.id, type: :ios}

      {:ok, device1} = Playback.register_device(attrs1)
      {:ok, device2} = Playback.register_device(attrs2)

      # Same device record
      assert device1.id == device2.id

      # But separate user links
      link1 = Ambry.Repo.get_by!(Playback.DeviceUser, device_id: device_id, user_id: user1.id)
      link2 = Ambry.Repo.get_by!(Playback.DeviceUser, device_id: device_id, user_id: user2.id)

      assert link1.user_id == user1.id
      assert link2.user_id == user2.id
    end
  end

  describe "record_events/1" do
    test "records multiple events" do
      playthrough = insert(:playthrough)

      events = [
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :start,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0"),
          media_id: playthrough.media_id
        },
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :play,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0")
        },
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :pause,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
          position: Decimal.new("100"),
          playback_rate: Decimal.new("1.0")
        }
      ]

      assert {:ok, 3} = Playback.record_events(events, playthrough.user_id)
    end

    test "a duplicate start event does not reset progress made since the real start" do
      playthrough = insert(:playthrough)

      real_start = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      progress_made = DateTime.add(real_start, 60, :second)
      reopened = DateTime.add(real_start, 3600, :second)

      initial_events = [
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :start,
          timestamp: real_start,
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0"),
          media_id: playthrough.media_id
        },
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :pause,
          timestamp: progress_made,
          position: Decimal.new("100"),
          playback_rate: Decimal.new("1.0")
        }
      ]

      {:ok, 2} = Playback.record_events(initial_events, playthrough.user_id)
      assert Decimal.equal?(Playback.get_playthrough(playthrough.id).position, Decimal.new("100"))

      reopen_event = [
        %{
          id: Ecto.UUID.generate(),
          playthrough_id: playthrough.id,
          type: :start,
          timestamp: reopened,
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0"),
          media_id: playthrough.media_id
        }
      ]

      {:ok, 1} = Playback.record_events(reopen_event, playthrough.user_id)

      assert Decimal.equal?(Playback.get_playthrough(playthrough.id).position, Decimal.new("100"))
    end
  end

  describe "list_events_changed_since/2" do
    test "returns events inserted after the given time" do
      user = insert(:user)
      playthrough = insert(:playthrough, user: user)

      # Both events have realistic client timestamps (millisecond precision)
      # but different inserted_at times (when they were recorded on server)
      _old =
        insert(:playback_event,
          playthrough_id: playthrough.id,
          timestamp: ~U[2025-01-01 10:00:00.000Z],
          inserted_at: ~U[2025-01-01 10:00:00.000000Z]
        )

      new =
        insert(:playback_event,
          playthrough_id: playthrough.id,
          timestamp: ~U[2025-01-01 11:00:00.000Z],
          inserted_at: ~U[2025-01-02 10:00:00.000000Z]
        )

      # Client sends lastSyncTime with millisecond precision
      since = ~U[2025-01-01 12:00:00.000Z]
      events = Playback.list_events_changed_since(user.id, since)

      assert length(events) == 1
      assert hd(events).id == new.id
    end
  end
end
