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

  # `media_tracks` names every file a recording is served from, so those are
  # exactly what deletion removes — and nothing else. No folder is handed to
  # `rm_rf` at all, which is what makes "did I just delete someone else's
  # audio" un-askable rather than answered correctly.
  describe "a recording with tracks" do
    test "deletes the files its tracks name, not whatever source_path says" do
      library = new_dir("library")
      folder = Path.join(library, "Some Author/Some Book")
      File.mkdir_p!(folder)
      file = Path.join(folder, "book.m4b")
      File.write!(file, "audio")

      # The vestigial upload-era folder: still named by the column, nothing
      # of this recording in it, and emphatically not Ambry's to remove.
      stale = new_dir("stale-source")
      bystander = Path.join(stale, "someone-elses.m4b")
      File.write!(bystander, "not ours")

      root = insert(:root, path: library)

      media =
        insert(:media,
          book: build(:book),
          source_path: Ambry.Paths.disk_to_web(stale),
          source_files: [],
          mpd_path: nil,
          hls_path: nil,
          mp4_path: nil
        )

      insert(:media_track,
        media: media,
        library_root_id: root.id,
        path: "Some Author/Some Book/book.m4b"
      )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.exists?(file)
      assert File.read!(bystander) == "not ours"
      assert File.dir?(stale)
    end

    # The real shared case: a book folder holds every recording of that book,
    # and a single-file recording sits directly in it.
    test "leaves a sibling recording's file in the folder they share" do
      library = new_dir("library")
      root = insert(:root, path: library)

      folder = Path.join(library, "Some Book")
      File.mkdir_p!(folder)
      mine = Path.join(folder, "mine.m4b")
      theirs = Path.join(folder, "theirs.m4b")
      File.write!(mine, "audio")
      File.write!(theirs, "sibling")

      media = insert(:media, book: build(:book), mpd_path: nil, hls_path: nil, mp4_path: nil)
      sibling = insert(:media, book: build(:book), mpd_path: nil, hls_path: nil, mp4_path: nil)
      insert(:media_track, media: media, library_root_id: root.id, path: "Some Book/mine.m4b")

      insert(:media_track,
        media: sibling,
        library_root_id: root.id,
        path: "Some Book/theirs.m4b"
      )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.exists?(mine)
      assert File.read!(theirs) == "sibling"
      assert File.dir?(folder)
    end

    # Tidiness, not correctness: once the files are gone the folder they were
    # in is empty and worth clearing, walking up until something is left.
    test "prunes the folders its files leave empty, stopping at the root" do
      library = new_dir("library")
      root = insert(:root, path: library)

      folder = Path.join(library, "Some Author/Some Book")
      File.mkdir_p!(folder)
      file = Path.join(folder, "book.m4b")
      File.write!(file, "audio")

      media = insert(:media, book: build(:book), mpd_path: nil, hls_path: nil, mp4_path: nil)

      insert(:media_track,
        media: media,
        library_root_id: root.id,
        path: "Some Author/Some Book/book.m4b"
      )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.dir?(folder)
      refute File.dir?(Path.join(library, "Some Author"))
      assert File.dir?(library)
    end

    test "stops pruning where the author still has another book" do
      library = new_dir("library")
      root = insert(:root, path: library)

      author = Path.join(library, "Some Author")
      keeper = Path.join([author, "Another Book", "keep.m4b"])
      File.mkdir_p!(Path.dirname(keeper))
      File.write!(keeper, "another book")

      folder = Path.join(author, "Some Book")
      File.mkdir_p!(folder)
      file = Path.join(folder, "book.m4b")
      File.write!(file, "audio")

      media = insert(:media, book: build(:book), mpd_path: nil, hls_path: nil, mp4_path: nil)

      insert(:media_track,
        media: media,
        library_root_id: root.id,
        path: "Some Author/Some Book/book.m4b"
      )

      assert {:ok, _media} = Media.delete_media(media)
      run_deletion_jobs()

      refute File.dir?(folder)
      assert File.exists?(keeper)
      assert File.dir?(author)
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
