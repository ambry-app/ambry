defmodule Ambry.Media.DeletionCustodyTest do
  @moduledoc """
  What deleting a recording is allowed to do to the bytes.

  Since the custody collapse the answer is structural rather than a flag:
  deletion removes *Ambry's name* for the bytes — the file in the library
  root — and the original a placement was made from is untouched by
  construction. A hardlink's original is a separate name for the same
  inode, a symlink is unlinked without being followed, a copy never knew
  its original. Getting this wrong doesn't produce a wrong page — it
  produces `rm -rf` on a folder the operator never gave Ambry.
  """
  use Ambry.DataCase

  alias Ambry.Media

  describe "deleting a recording" do
    test "removes the library files it owns" do
      %{media: media, folder: folder, file: file} = library_media()

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
          source_path: Ambry.Paths.disk_to_web(folder),
          source_files: [Ambry.Paths.disk_to_web(file)],
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
          source_path: Ambry.Paths.disk_to_web(folder),
          source_files: [Ambry.Paths.disk_to_web(file)],
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
      %{media: media, file: file} = library_media()

      seeding = Path.join(System.tmp_dir!(), "seeding-#{Ecto.UUID.generate()}.m4b")
      File.ln!(file, seeding)
      on_exit(fn -> File.rm(seeding) end)

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.exists?(file)
      assert File.read!(seeding) == "audio"
    end

    # The symlink door's version of the same promise: `File.rm_rf` unlinks a
    # symlink without following it, so deleting a symlinked recording removes
    # the library's pointers and never the operator's originals.
    test "removing a symlinked recording leaves the targets alone" do
      original_folder = new_dir("originals")
      original = Path.join(original_folder, "book.m4b")
      File.write!(original, "audio")

      folder = new_dir("library")
      file = Path.join(folder, "book.m4b")
      File.ln_s!(original, file)

      media =
        insert(:media,
          book: build(:book),
          source_path: Ambry.Paths.disk_to_web(folder),
          source_files: [Ambry.Paths.disk_to_web(file)],
          mpd_path: nil,
          hls_path: nil,
          mp4_path: nil
        )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.dir?(folder)
      assert File.read!(original) == "audio"
    end
  end

  describe "replacing a recording's files" do
    # The old folder is Ambry's name for the bytes and goes with the
    # replacement, exactly like deletion.
    test "removes the old source folder once the new files are in place" do
      %{media: media, folder: folder, file: file} = library_media()
      new_folder = new_dir("replacement")
      new_file = Path.join(new_folder, "better.m4b")
      File.write!(new_file, "better audio")

      assert {:ok, _media} =
               Media.replace_media(media, %{
                 source_path: Ambry.Paths.disk_to_web(new_folder),
                 source_files: [Ambry.Paths.disk_to_web(new_file)],
                 processor: :mp4_concat
               })

      run_deletion_jobs()

      refute File.exists?(file)
      refute File.dir?(folder)
    end
  end

  defp library_media do
    folder = new_dir("library")
    file = Path.join(folder, "book.m4b")
    File.write!(file, "audio")

    media =
      insert(:media,
        book: build(:book),
        source_path: Ambry.Paths.disk_to_web(folder),
        source_files: [Ambry.Paths.disk_to_web(file)],
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
