defmodule Ambry.Media.AuditTest do
  use Ambry.DataCase

  alias Ambry.Media.Audit

  describe "get_media_file_details/1" do
    test "returns source file details" do
      %{source_path: source_path} = media = insert(:media, mpd_path: nil, mp4_path: nil, hls_path: nil)

      create_fake_source_files!(source_path)

      assert audit = Audit.get_media_file_details(media)

      assert %{
               source_files: [
                 %{
                   path: bar_mp3_path,
                   stat: %File.Stat{}
                 },
                 %{
                   path: baz_mp3_path,
                   stat: %File.Stat{}
                 },
                 %{
                   path: foo_mp3_path,
                   stat: %File.Stat{}
                 },
                 %{
                   path: out_files_txt_path,
                   stat: %File.Stat{}
                 }
               ]
             } = audit

      assert "foo.mp3" = Path.basename(foo_mp3_path)
      assert "bar.mp3" = Path.basename(bar_mp3_path)
      assert "baz.mp3" = Path.basename(baz_mp3_path)
      assert "files.txt" = Path.basename(out_files_txt_path)
    end

    test "when source folder is missing" do
      media = insert(:media, mpd_path: nil, mp4_path: nil, hls_path: nil)

      assert audit = Audit.get_media_file_details(media)

      assert %{source_files: :enoent} = audit
    end

    test "returns media file details" do
      media = insert(:media)
      create_fake_files!(media)

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

      create_fake_files!(media1)
      create_fake_files!(media2)

      # an orphaned source folder with a file in it
      orphaned_source_path = Ambry.Paths.source_media_disk_path(Ecto.UUID.generate())
      create_fake_source_files!(orphaned_source_path)

      # an orphaned mp4 file
      File.touch!(Ambry.Paths.web_to_disk("/uploads/media/#{Ecto.UUID.generate()}.mp4"))

      # a missing mp4 file
      File.rm_rf!(Ambry.Paths.web_to_disk(media1.mp4_path))

      # a missing source folder
      File.rm_rf!(media2.source_path)

      assert %{
               orphaned_source_folders: _,
               orphaned_media_files: _,
               broken_media: _
             } = Audit.orphaned_files_audit()
    end
  end
end
