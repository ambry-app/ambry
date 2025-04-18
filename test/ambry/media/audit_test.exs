defmodule Ambry.Media.AuditTest do
  use Ambry.DataCase

  alias Ambry.Media.Audit

  describe "get_media_file_details/1" do
    test "returns source file details" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      assert audit = Audit.get_media_file_details(media)

      assert %{
               hls_master: %{
                 path: hls_master_path,
                 stat: %File.Stat{}
               },
               hls_playlist: %{
                 path: hls_playlist_path,
                 stat: %File.Stat{}
               },
               mp4_file: %{
                 path: mp4_path,
                 stat: %File.Stat{}
               },
               mpd_file: %{
                 path: mpd_path,
                 stat: %File.Stat{}
               }
             } = audit

      assert is_binary(hls_master_path)
      assert is_binary(hls_playlist_path)
      assert is_binary(mp4_path)
      assert is_binary(mpd_path)
    end

    test "when source folder is missing" do
      media = insert(:media, source_path: "/some/path", book: build(:book))

      assert audit = Audit.get_media_file_details(media)

      assert %{source_files: :enoent} = audit
    end

    test "returns media file details" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      assert audit = Audit.get_media_file_details(media)

      assert %{
               hls_master: %{path: "" <> _, stat: %File.Stat{}},
               hls_playlist: %{path: "" <> _, stat: %File.Stat{}},
               mp4_file: %{path: "" <> _, stat: %File.Stat{}},
               mpd_file: %{path: "" <> _, stat: %File.Stat{}}
             } = audit
    end

    test "when media file is missing" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

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
      media1 =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      media2 =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      # an orphaned source folder with a file in it
      orphaned_source_path = valid_source_path()
      File.write!(Path.join(orphaned_source_path, "test.mp3"), "test")

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
