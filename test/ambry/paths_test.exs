defmodule Ambry.PathsTest do
  use Ambry.DataCase

  alias Ambry.Paths

  describe "uploads_folder_disk_path/0" do
    test "returns the disk path of the uploads folder" do
      assert "" <> _path = Paths.uploads_folder_disk_path()
    end
  end

  describe "uploads_folder_disk_path/1" do
    test "returns the disk path of a file within the uploads folder" do
      path = Paths.uploads_folder_disk_path("foo.txt")

      assert Path.basename(path) == "foo.txt"
    end
  end

  describe "source_media_disk_path/0" do
    test "returns the disk path of the source media folder" do
      assert "" <> _path = Paths.source_media_disk_path()
    end
  end

  describe "source_media_disk_path/1" do
    test "returns the disk path of a file within the source media folder" do
      path = Paths.source_media_disk_path("foo.txt")

      assert Path.basename(path) == "foo.txt"
    end
  end

  describe "media_disk_path/0" do
    test "returns the disk path of the media folder" do
      assert "" <> _path = Paths.media_disk_path()
    end
  end

  describe "media_disk_path/1" do
    test "returns the disk path of a file within the media folder" do
      path = Paths.media_disk_path("foo.txt")

      assert Path.basename(path) == "foo.txt"
    end
  end

  describe "images_disk_path/0" do
    test "returns the disk path of the images folder" do
      assert "" <> _path = Paths.images_disk_path()
    end
  end

  describe "images_disk_path/1" do
    test "returns the disk path of a file within the images folder" do
      path = Paths.images_disk_path("foo.txt")

      assert Path.basename(path) == "foo.txt"
    end
  end

  describe "web_to_disk/1" do
    test "converts web paths to disk paths" do
      assert Paths.web_to_disk("/uploads/images/foo.png") == Paths.images_disk_path("foo.png")
      assert Paths.web_to_disk("/uploads/media/foo.mpd") == Paths.media_disk_path("foo.mpd")
    end
  end

  describe "hls_playlist_path/1" do
    test "converts an hls manifest path to an hls playlist path" do
      assert Paths.hls_playlist_path("/uploads/media/foo.m3u8") == "/uploads/media/foo_0.m3u8"
    end
  end
end
