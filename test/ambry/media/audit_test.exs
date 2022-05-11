defmodule Ambry.Media.AuditTest do
  use Ambry.DataCase

  alias Ambry.Media.Audit

  describe "get_media_file_details/1" do
    test "returns source file details" do
      media = insert(:media, mpd_path: nil, mp4_path: nil, hls_path: nil)

      # put a fake file in the source folder
      File.touch!(Path.join([media.source_path, "foo.mp3"]))

      assert audit = Audit.get_media_file_details(media)

      assert %{
               source_files: [
                 %{
                   path: mp3_file_path,
                   stat: %File.Stat{}
                 }
               ]
             } = audit

      assert "foo.mp3" = Path.basename(mp3_file_path)
    end

    test "returns details from sub-folders of the source folder" do
      media = insert(:media, mpd_path: nil, mp4_path: nil, hls_path: nil)

      # put some fake files into the source folder
      File.mkdir!(Path.join([media.source_path, "foo"]))
      File.touch!(Path.join([media.source_path, "foo", "bar.txt"]))

      assert audit = Audit.get_media_file_details(media)

      assert %{
               source_files: [
                 %{
                   path: txt_file_path,
                   stat: %File.Stat{}
                 }
               ]
             } = audit

      assert "bar.txt" = Path.basename(txt_file_path)
    end

    test "when source folder is missing" do
      media = insert(:media, mpd_path: nil, mp4_path: nil, hls_path: nil)

      File.rm_rf!(media.source_path)

      assert audit = Audit.get_media_file_details(media)

      assert %{source_files: :enoent} = audit
    end

    test "returns media file details" do
      media = insert(:media)

      assert audit = Audit.get_media_file_details(media)

      assert %{
               hls_master: %{path: "" <> _, stat: %File.Stat{}},
               hls_playlist: %{path: "" <> _, stat: %File.Stat{}},
               mp4_file: %{path: "" <> _, stat: %File.Stat{}},
               mpd_file: %{path: "" <> _, stat: %File.Stat{}}
             } = audit
    end

    test "when media file is missing" do
      media = insert(:media)

      File.rm_rf!(Ambry.Paths.web_to_disk(media.mp4_path))

      assert audit = Audit.get_media_file_details(media)

      assert %{mp4_file: %{stat: :enoent}} = audit
    end
  end

  describe "count_files/0" do
    test "returns the number of files in the media uploads folder" do
      assert is_integer(Audit.count_files())
    end
  end

  describe "orphaned_files_audit/0" do
    test "returns a report of files on disk that are not associated with the database" do
      media1 = insert(:media)
      media2 = insert(:media)

      File.mkdir!(Ambry.Paths.source_media_disk_path(Ecto.UUID.generate()))
      File.rm_rf!(Ambry.Paths.web_to_disk(media1.mp4_path))
      File.rm_rf!(media2.source_path)

      assert %{
               orphaned_source_folders: _,
               orphaned_media_files: _,
               broken_media: _
             } = Audit.orphaned_files_audit()
    end
  end
end
