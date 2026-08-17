defmodule Ambry.SettingsTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Settings

  describe "direct_play_publishing?/0" do
    test "is off until an operator turns it on" do
      refute Settings.direct_play_publishing?()
    end

    test "remembers being turned on and off again" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      assert Settings.direct_play_publishing?()

      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      refute Settings.direct_play_publishing?()
    end
  end

  describe "the publishing gate" do
    test "a direct-play recording can't be published while the switch is off" do
      media = scanned_media()

      assert {:error, changeset} = Media.update_media(media, %{status: :ready})

      assert %{status: ["can't be ready: direct-play publishing is switched off"]} =
               errors_on(changeset)
    end

    test "and can be once it's on" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      media = scanned_media()

      assert {:ok, media} = Media.update_media(media, %{status: :ready})
      assert media.status == :ready
    end

    test "doesn't strand recordings published before it was switched back off" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      {:ok, media} = scanned_media() |> Media.update_media(%{status: :ready})

      {:ok, _setting} = Settings.set_direct_play_publishing(false)

      media = Media.get_media!(media.id)
      assert {:ok, media} = Media.update_media(media, %{notes: "still live"})
      assert media.status == :ready
    end

    test "doesn't stop a scanned recording from being edited otherwise" do
      media = scanned_media()

      assert {:ok, media} = Media.update_media(media, %{notes: "not published, still editable"})
      assert media.status == :pending
    end

    test "doesn't touch legacy recordings, which have their own requirement" do
      media = insert(:media, book: build(:book))

      assert {:error, changeset} = Media.update_media(media, %{status: :ready})

      # the legacy artifacts are what's missing here, not the switch
      assert %{mp4_path: ["can't be blank"]} = errors_on(changeset)
      refute Map.has_key?(errors_on(changeset), :status)
    end

    test "a caller can state the gate itself rather than read the setting" do
      media = scanned_media()

      assert {:ok, media} =
               Media.update_media(media, %{status: :ready}, direct_play_publishing?: true)

      assert media.status == :ready
    end
  end

  defp scanned_media do
    :media
    |> build(book: build(:book))
    |> insert()
    |> with_probed_tracks()
  end
end
