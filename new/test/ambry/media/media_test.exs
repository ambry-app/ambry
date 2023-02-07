defmodule Ambry.Media.MediaTest do
  use Ambry.DataCase

  alias Ambry.Media.Media

  describe "source_id/1" do
    test "generates a new UUID if a source_path doesn't yet exist" do
      uuid = Media.source_id(%Media{})
      assert {:ok, _} = Ecto.UUID.cast(uuid)
    end

    test "returns the existing source_path id if it exists" do
      media = build(:media)

      uuid = Media.source_id(media)
      assert {:ok, _} = Ecto.UUID.cast(uuid)
      assert media.source_path =~ uuid
    end
  end

  describe "source_path/1" do
    test "returns the path to the source folder of a media" do
      media = build(:media)
      uuid = Media.source_id(media)

      path = Media.source_path(media)

      assert path =~ uuid
    end
  end

  describe "source_path/2" do
    test "returns the path to a source file within the source folder of a media" do
      media = build(:media)
      uuid = Media.source_id(media)

      path = Media.source_path(media, "foo.txt")

      assert path =~ "foo.txt"
      assert path =~ uuid
    end
  end

  describe "output_id/1" do
    test "generates a new UUID if no output files exist yet" do
      media = insert(:media, source_path: nil, mp4_path: nil, mpd_path: nil, hls_path: nil)

      uuid = Media.output_id(media)
      assert {:ok, _} = Ecto.UUID.cast(uuid)
    end

    test "returns the existing output id if it exists" do
      media = build(:media)

      uuid = Media.output_id(media)
      assert {:ok, _} = Ecto.UUID.cast(uuid)
      assert media.mp4_path =~ uuid
    end
  end

  describe "out_path/1" do
    test "returns the path to the output folder of a media" do
      media = build(:media)
      uuid = Media.source_id(media)

      path = Media.out_path(media)

      assert path =~ uuid
    end
  end

  describe "out_path/2" do
    test "returns the path to an output file within the output folder of a media" do
      media = build(:media)
      uuid = Media.source_id(media)

      path = Media.out_path(media, "foo.mp4")

      assert path =~ "foo.mp4"
      assert path =~ uuid
    end
  end

  describe "files/2" do
    test "returns a list of files with given extension from the media source path" do
      media = build(:media)
      create_fake_files!(media)

      files = Media.files(media, [".mp3"])

      assert ["bar.mp3", "baz.mp3", "foo.mp3"] = files
    end

    test "returns full paths too" do
      media = build(:media)
      create_fake_files!(media)

      files = Media.files(media, [".mp3"], full?: true)

      assert length(files) == 3
    end

    test "if the media's source path does not exist, returns an empty list" do
      media = build(:media)

      files = Media.files(media, [".mp3"])

      assert [] = files
    end
  end
end
