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

  describe "upsert_playthrough/1" do
    test "creates a new playthrough" do
      user = insert(:user)
      media = insert(:media, book: build(:book))

      attrs = %{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        media_id: media.id,
        status: :in_progress,
        started_at: DateTime.utc_now() |> DateTime.truncate(:millisecond)
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
        finished_at: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {:ok, updated} = Playback.upsert_playthrough(attrs)
      assert updated.id == playthrough.id
      assert updated.status == :finished
      assert updated.finished_at != nil
    end
  end

  describe "list_playthroughs_changed_since/2" do
    test "returns playthroughs updated after the given time" do
      user = insert(:user)
      old = insert(:playthrough, user: user, updated_at: ~U[2025-01-01 10:00:00.000Z])
      new = insert(:playthrough, user: user, updated_at: ~U[2025-01-02 10:00:00.000Z])

      since = ~U[2025-01-01 12:00:00.000Z]
      playthroughs = Playback.list_playthroughs_changed_since(user.id, since)

      assert length(playthroughs) == 1
      assert hd(playthroughs).id == new.id
      refute Enum.any?(playthroughs, &(&1.id == old.id))
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

      assert {:ok, 2} = Playback.record_events(events)
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
          playthrough: playthrough,
          timestamp: ~U[2025-01-01 10:00:00.000Z],
          inserted_at: ~U[2025-01-01 10:00:00.000000Z]
        )

      new =
        insert(:playback_event,
          playthrough: playthrough,
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
          started_at: DateTime.utc_now() |> DateTime.truncate(:millisecond)
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
          timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
          position: Decimal.new("0"),
          playback_rate: Decimal.new("1.0")
        }
      ]

      assert {:ok, 1} = Playback.sync_events(events_data)
    end
  end
end
