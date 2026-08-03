defmodule Ambry.Media.PublishingTest do
  @moduledoc """
  Getting an approved recording all the way to visible.

  The publishing switch exists so the server never hands a client a
  direct-play recording it can't play. That means approval can't simply
  publish — and it also means turning the switch on has to release everything
  that piled up behind it, or the operator would have to open and re-save
  every recording the inbox ever approved.
  """
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Repo
  alias Ambry.Settings

  describe "publish_pending_direct_play/0" do
    test "publishes a pending direct-play recording" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      media = direct_play_media()

      assert {:ok, %{published: 1, failed: 0}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :ready
    end

    # The switch governs the act of publishing. With it off, the changeset
    # itself refuses, and the sweep must report that rather than pretending.
    test "publishes nothing while the switch is off" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      media = direct_play_media()

      assert {:ok, %{published: 0, failed: 1}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :pending
    end

    # A legacy recording sitting in `pending` is waiting on transcoding, not
    # on this switch.
    test "leaves a legacy recording alone" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)

      media =
        insert(:media,
          book: build(:book),
          status: :pending,
          mp4_path: "/uploads/media/x.mp4",
          hls_path: nil,
          mpd_path: nil
        )

      assert {:ok, %{published: 0}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :pending
    end

    # Publishing a recording whose files have vanished would hand clients
    # something unplayable.
    test "skips a recording whose files are missing" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      media = direct_play_media(missing_since: DateTime.utc_now(:second))

      assert {:ok, %{published: 0}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :pending
    end

    test "leaves an already-published recording alone" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      media = direct_play_media(status: :ready)

      assert {:ok, %{published: 0}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :ready
    end

    # A recording with several tracks would otherwise be counted once per
    # track by the join.
    test "counts a multi-track recording once" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)

      media =
        insert(:media,
          book: build(:book),
          status: :pending,
          mp4_path: nil,
          hls_path: nil,
          mpd_path: nil,
          media_tracks: [build(:media_track, index: 0), build(:media_track, index: 1)]
        )

      assert {:ok, %{published: 1}} = Media.publish_pending_direct_play()
      assert Repo.reload(media).status == :ready
    end
  end

  defp direct_play_media(opts \\ []) do
    insert(
      :media,
      Keyword.merge(
        [
          book: build(:book),
          status: :pending,
          mp4_path: nil,
          hls_path: nil,
          mpd_path: nil,
          media_tracks: [build(:media_track)]
        ],
        opts
      )
    )
  end
end
