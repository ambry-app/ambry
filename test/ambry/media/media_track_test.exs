defmodule Ambry.Media.MediaTrackTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.MediaTrack

  describe "changeset/2" do
    test "requires the facts a client needs to play the file" do
      changeset = MediaTrack.changeset(%MediaTrack{}, %{})

      assert %{
               index: ["can't be blank"],
               path: ["can't be blank"],
               size: ["can't be blank"],
               duration: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects a zero-length track" do
      changeset = MediaTrack.changeset(%MediaTrack{}, params_for(:media_track, duration: "0"))

      assert %{duration: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects a negative start offset" do
      changeset =
        MediaTrack.changeset(%MediaTrack{}, params_for(:media_track, start_offset: "-1"))

      assert %{start_offset: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "defaults to exact seeking" do
      changeset = MediaTrack.changeset(%MediaTrack{}, params_for(:media_track))

      assert %MediaTrack{seek_accuracy: :exact} = apply_changes(changeset)
    end
  end

  describe "range/1" do
    test "returns the absolute book-seconds the track covers" do
      track = build(:media_track, start_offset: Decimal.new("60.5"), duration: Decimal.new("120"))

      assert {start_time, end_time} = MediaTrack.range(track)
      assert Decimal.equal?(start_time, "60.5")
      assert Decimal.equal?(end_time, "180.5")
    end
  end

  describe "tracks on a media" do
    test "are persisted in order" do
      media = :media |> insert(book: build(:book)) |> then(&Media.get_media!(&1.id))

      {:ok, media} =
        Media.update_media(media, %{
          media_tracks: [
            params_for(:media_track, index: 1, start_offset: "3600"),
            params_for(:media_track, index: 0, start_offset: "0")
          ]
        })

      assert [%MediaTrack{index: 0}, %MediaTrack{index: 1}] =
               Media.get_media!(media.id).media_tracks
    end

    test "cannot share an index within one media" do
      media = insert(:media, book: build(:book))

      assert_raise Ecto.ConstraintError, fn ->
        insert_list(2, :media_track, media: media, index: 0)
      end
    end

    test "are deleted with their media" do
      media = insert(:media, book: build(:book))
      insert(:media_track, media: media)

      {:ok, _media} = Media.delete_media(media)

      assert Repo.aggregate(MediaTrack, :count) == 0
    end
  end

  describe "readiness validation" do
    test "a media with tracks is ready without the legacy packaged artifacts" do
      media = :media |> insert(book: build(:book)) |> then(&Media.get_media!(&1.id))

      assert {:ok, media} =
               Media.update_media(media, %{
                 status: :ready,
                 media_tracks: [params_for(:media_track)]
               })

      assert media.status == :ready
      assert is_nil(media.mp4_path)
    end

    test "a media without tracks still requires them" do
      media = insert(:media, book: build(:book))

      assert {:error, changeset} = Media.update_media(media, %{status: :ready})

      assert %{
               mpd_path: ["can't be blank"],
               hls_path: ["can't be blank"],
               mp4_path: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "an existing direct-play media stays editable without them" do
      media = insert(:media, book: build(:book), status: :ready)
      insert(:media_track, media: media)

      media = Media.get_media!(media.id)

      assert {:ok, media} = Media.update_media(media, %{notes: "still direct-play"})
      assert media.notes == "still direct-play"
    end
  end
end
