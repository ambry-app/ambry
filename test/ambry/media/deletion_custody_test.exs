defmodule Ambry.Media.DeletionCustodyTest do
  @moduledoc """
  What deleting a recording is allowed to do to the bytes.

  Custody is the whole answer: `managed` means Ambry owns the files and may
  remove them; `external` means the files belong to someone else's workflow
  and removal deletes records only. Getting this wrong doesn't produce a
  wrong page — it produces `rm -rf` on a folder the operator never gave
  Ambry permission to touch.
  """
  use Ambry.DataCase

  alias Ambry.Media

  describe "external custody" do
    # The promise external custody makes is the entire reason it exists: the
    # files are referenced where they lie and Ambry never writes to them.
    # `delete_media` used to hand `source_path` to a worker that runs
    # `File.rm_rf` on it — which for an inbox-approved recording is the
    # operator's own downloads folder.
    test "deleting a recording never touches the source folder" do
      %{media: media, folder: folder, file: file} = external_media()

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      assert File.exists?(file), "external source file was deleted"
      assert File.dir?(folder), "external source folder was deleted"
    end

    test "the records are gone even though the files remain" do
      %{media: media} = external_media()

      assert {:ok, _media} = Media.delete_media(media)

      assert_raise Ecto.NoResultsError, fn -> Media.get_media!(media.id) end
    end
  end

  describe "replacing an external recording's files" do
    # Replace deletes the *old* source folder once the new files are in
    # place, which for an external recording is again the operator's own
    # folder rather than Ambry's.
    test "leaves the original source folder alone" do
      %{media: media, folder: folder, file: file} = external_media()
      new_folder = new_dir("replacement")
      new_file = Path.join(new_folder, "better.m4b")
      File.write!(new_file, "better audio")

      assert {:ok, _media} =
               Media.replace_media(media, %{
                 source_path: new_folder,
                 source_files: [new_file],
                 processor: :mp4_concat
               })

      run_deletion_jobs()

      assert File.exists?(file)
      assert File.dir?(folder)
    end
  end

  describe "managed custody" do
    test "deleting a recording removes the library files it owns" do
      %{media: media, folder: folder, file: file} = managed_media()

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.exists?(file)
      refute File.dir?(folder)
    end

    # A library tree that only ever accumulates empty author and series
    # folders isn't organized for long.
    test "prunes the folders left empty behind it" do
      root = new_dir("root")
      insert(:root, path: root)

      folder =
        Path.join([root, "Brandon Sanderson", "The Stormlight Archive", "The Way of Kings"])

      File.mkdir_p!(folder)
      file = Path.join(folder, "book.m4b")
      File.write!(file, "audio")

      media =
        insert(:media,
          book: build(:book),
          custody: :managed,
          source_path: folder,
          source_files: [file],
          mpd_path: nil,
          hls_path: nil,
          mp4_path: nil
        )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.dir?(Path.join([root, "Brandon Sanderson", "The Stormlight Archive"]))
      refute File.dir?(Path.join(root, "Brandon Sanderson"))
      # the root itself is configuration, not a consequence of holding a book
      assert File.dir?(root)
    end

    test "stops pruning at a folder that still holds another book" do
      root = new_dir("root")
      insert(:root, path: root)

      author = Path.join(root, "Brandon Sanderson")
      keeper = Path.join([author, "Warbreaker", "Warbreaker.m4b"])
      File.mkdir_p!(Path.dirname(keeper))
      File.write!(keeper, "another book")

      folder = Path.join(author, "The Way of Kings")
      File.mkdir_p!(folder)
      file = Path.join(folder, "book.m4b")
      File.write!(file, "audio")

      media =
        insert(:media,
          book: build(:book),
          custody: :managed,
          source_path: folder,
          source_files: [file],
          mpd_path: nil,
          hls_path: nil,
          mp4_path: nil
        )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.dir?(folder)
      assert File.exists?(keeper)
      assert File.dir?(author)
    end

    # A hardlink is one inode with two names. Removing the library's name
    # leaves the seeding copy untouched — that's inherent to hardlinks, and
    # it's precisely why hardlinking is safe to delete from.
    test "removing a hardlinked file leaves the other link alone" do
      %{media: media, file: file} = managed_media()

      seeding = Path.join(System.tmp_dir!(), "seeding-#{Ecto.UUID.generate()}.m4b")
      File.ln!(file, seeding)
      on_exit(fn -> File.rm(seeding) end)

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.exists?(file)
      assert File.read!(seeding) == "audio"
    end
  end

  defp external_media do
    folder = new_dir("external")
    file = Path.join(folder, "book.m4b")
    File.write!(file, "audio")

    media =
      insert(:media,
        book: build(:book),
        custody: :external,
        source_path: folder,
        source_files: [file],
        mpd_path: nil,
        hls_path: nil,
        mp4_path: nil
      )

    %{media: media, folder: folder, file: file}
  end

  defp managed_media do
    folder = new_dir("managed")
    file = Path.join(folder, "book.m4b")
    File.write!(file, "audio")

    media =
      insert(:media,
        book: build(:book),
        custody: :managed,
        source_path: folder,
        source_files: [file],
        mpd_path: nil,
        hls_path: nil,
        mp4_path: nil
      )

    %{media: media, folder: folder, file: file}
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end

  # Deletion is scheduled rather than immediate, so the assertions have to
  # wait for the worker rather than for the function to return.
  defp run_deletion_jobs do
    Oban.drain_queue(queue: :default)
  end
end
