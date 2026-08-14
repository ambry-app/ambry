defmodule Ambry.LibraryTest do
  use Ambry.DataCase

  alias Ambry.Library
  alias Ambry.Library.Root
  alias Ambry.Library.Source

  describe "create_source/1" do
    test "creates a source" do
      assert {:ok, %Source{} = source} =
               Library.create_source(%{
                 name: "Downloads",
                 path: "/data/downloads"
               })

      assert source.path == "/data/downloads"
      assert source.enabled
      assert is_nil(source.last_scanned_at)
    end

    test "defaults to hardlinking" do
      assert {:ok, source} =
               Library.create_source(%{name: "D", path: "/data/d"})

      assert source.import_policy == :hardlink
    end

    test "keeps an explicit import policy" do
      assert {:ok, source} =
               Library.create_source(%{
                 name: "D",
                 path: "/data/d",
                 import_policy: :move
               })

      assert source.import_policy == :move
    end

    test "requires an absolute path" do
      assert {:error, changeset} =
               Library.create_source(%{name: "D", path: "relative/path"})

      assert "must be an absolute path" in errors_on(changeset).path
    end

    test "normalizes surrounding whitespace and a trailing slash" do
      assert {:ok, source} =
               Library.create_source(%{
                 name: "D",
                 path: "  /data/downloads/  "
               })

      assert source.path == "/data/downloads"
    end

    test "refuses a duplicate path" do
      insert(:source, path: "/data/downloads")

      assert {:error, changeset} =
               Library.create_source(%{
                 name: "Other",
                 path: "/data/downloads"
               })

      assert "has already been taken" in errors_on(changeset).path
    end

    test "refuses a duplicate name" do
      insert(:source, name: "Downloads")

      assert {:error, changeset} =
               Library.create_source(%{
                 name: "Downloads",
                 path: "/data/other"
               })

      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "create_root/1" do
    test "creates a root" do
      assert {:ok, %Root{} = root} =
               Library.create_root(%{name: "Library", path: "/data/library"})

      assert root.path == "/data/library"
    end

    test "keeps the filesystem root path intact" do
      assert {:ok, root} = Library.create_root(%{name: "R", path: "/"})

      assert root.path == "/"
    end

    test "requires an absolute path" do
      assert {:error, changeset} = Library.create_root(%{name: "R", path: "relative"})

      assert "must be an absolute path" in errors_on(changeset).path
    end
  end

  describe "stored-path resolution" do
    test "resolves a root-relative path" do
      root = insert(:root, path: "/data/library")

      assert Library.resolve(root, "Author/Book (2010)/Book.m4b") ==
               {:ok, "/data/library/Author/Book (2010)/Book.m4b"}

      assert Library.resolve(root.id, "Book.m4b") == {:ok, "/data/library/Book.m4b"}
    end

    test "resolves a legacy /uploads path with no root" do
      assert {:ok, resolved} = Library.resolve(nil, "/uploads/source_media/abc")
      assert resolved == Ambry.Paths.web_to_disk("/uploads/source_media/abc")
    end

    # These feed `File.rm_rf`, so the refusals are the first check, not an
    # afterthought.
    test "refuses traversal and absolute paths before anything else" do
      root = insert(:root, path: "/data/library")

      assert {:error, {:traversal, _path}} = Library.resolve(root, "../outside/Book.m4b")
      assert {:error, {:traversal, _path}} = Library.resolve(root, "Author/../../etc/passwd")
      assert {:error, {:not_relative, _path}} = Library.resolve(root, "/etc/passwd")
      assert {:error, {:unresolvable, _path}} = Library.resolve(nil, "/anywhere/else")
    end

    # The real library has spaces, brackets and unicode in nearly every path.
    test "relativize then resolve round-trips awkward real-world paths" do
      root = insert(:root, path: "/data/library")

      for path <- [
            "/data/library/Sarah J. Maas/[ACOTAR #1] A Court of Thorns and Roses (chapterized)/01 – Chäpter Öne.m4b",
            "/data/library/single.m4b"
          ] do
        assert {:ok, relative} = Library.relativize(root, path)
        assert Library.resolve(root, relative) == {:ok, path}
      end
    end

    test "relativize refuses a path outside its location" do
      root = insert(:root, path: "/data/library")

      assert Library.relativize(root, "/data/library-other/Book.m4b") ==
               {:error, :outside_location}
    end

    test "locate picks the longest matching root on a segment boundary" do
      insert(:root, path: "/data")
      inner = insert(:root, path: "/data/library")
      insert(:root, path: "/data/library-other")

      assert {:ok, {root, "Book.m4b"}} = Library.locate("/data/library/Book.m4b")
      assert root.id == inner.id

      assert {:error, :no_location} = Library.locate("/somewhere/else.m4b")
    end

    # The motivating regression: the library moved mounts and every stored
    # absolute path broke. Now the mount is one row, and every dependent
    # resolution follows it with zero row updates.
    test "a changed root path carries every resolution with it" do
      root = insert(:root, path: "/mnt/old-nas/library")

      media =
        insert(:media,
          book: build(:book),
          library_root_id: root.id,
          source_path: "Author/Book",
          source_files: ["Author/Book/book.m4b"],
          media_tracks: [
            build(:media_track, path: "Author/Book/book.m4b", library_root_id: root.id)
          ]
        )

      {:ok, _root} = Library.update_root(root, %{path: "/srv/media/library"})

      media = Repo.reload(media) |> Repo.preload([:media_tracks, :library_root], force: true)

      assert Ambry.Media.Media.source_path(media) == "/srv/media/library/Author/Book"

      assert Ambry.Media.Media.source_file_paths(media) ==
               ["/srv/media/library/Author/Book/book.m4b"]

      assert [track] = media.media_tracks

      assert Ambry.Media.MediaTrack.disk_path(track) ==
               {:ok, "/srv/media/library/Author/Book/book.m4b"}
    end
  end

  describe "deleting a referenced location" do
    test "a root holding recordings refuses with reference counts" do
      root = insert(:root)

      insert(:media,
        book: build(:book),
        library_root_id: root.id,
        source_path: "Author/Book",
        source_files: ["Author/Book/book.m4b"],
        media_tracks: [
          build(:media_track, path: "Author/Book/book.m4b", library_root_id: root.id)
        ]
      )

      assert {:error, {:referenced, %{media: 1, media_tracks: 1}}} = Library.delete_root(root)
      assert {:ok, _root} = Library.fetch_root(root.id)
    end

    test "a source with queued items refuses with reference counts" do
      source = insert(:source)

      Repo.insert!(%Ambry.Inbox.InboxItem{
        source_id: source.id,
        path: "Some Release",
        files: ["Some Release/book.m4b"]
      })

      assert {:error, {:referenced, %{inbox_items: 1}}} = Library.delete_source(source)
      assert {:ok, _source} = Library.fetch_source(source.id)
    end

    # The app-level refusal explains; the FK refuses even code that skips it.
    test "the database refuses too" do
      root = insert(:root)

      insert(:media,
        book: build(:book),
        library_root_id: root.id,
        source_path: "Author/Book"
      )

      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(root) end
    end
  end

  describe "the stored-path constraints" do
    # The resolver's refusals protect the filesystem; these protect the
    # database from code that never went through the resolver.
    test "a rooted media may not store an absolute path" do
      root = insert(:root)

      assert_raise Postgrex.Error, ~r/media_source_path_resolvable/, fn ->
        Repo.insert_all("media", [
          %{
            source_path: "/absolute/anywhere",
            library_root_id: root.id,
            full_cast: false,
            status: "pending",
            abridged: false,
            book_id: insert(:book).id,
            inserted_at: DateTime.utc_now(:second),
            updated_at: DateTime.utc_now(:second)
          }
        ])
      end
    end

    test "an unrooted track may only store an uploads path" do
      media = insert(:media, book: build(:book))

      assert_raise Postgrex.Error, ~r/media_tracks_path_resolvable/, fn ->
        Repo.insert_all("media_tracks", [
          %{
            media_id: media.id,
            index: 0,
            path: "/mnt/downloads/book.m4b",
            size: 1,
            duration: Decimal.new(1),
            start_offset: Decimal.new(0),
            inserted_at: DateTime.utc_now(:second),
            updated_at: DateTime.utc_now(:second)
          }
        ])
      end
    end

    test "a sourced inbox item may not store an absolute path" do
      source = insert(:source)

      assert_raise Postgrex.Error, ~r/inbox_items_path_locatable/, fn ->
        Repo.insert_all("inbox_items", [
          %{
            source_id: source.id,
            path: "/mnt/downloads/Some Release",
            files: ["Some Release/book.m4b"],
            status: "pending",
            inserted_at: DateTime.utc_now(:second),
            updated_at: DateTime.utc_now(:second)
          }
        ])
      end
    end
  end

  describe "listing" do
    test "sources and roots are separate registries" do
      source = insert(:source)
      root = insert(:root)
      paused = insert(:source, enabled: false)

      assert Library.list_sources() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([source.id, paused.id])

      assert Library.list_roots() |> Enum.map(& &1.id) == [root.id]
    end

    # Roots are never watched — watching is a source's job. An operator who
    # wants the library tree watched points a source at the same path.
    test "watched sources exclude paused ones and know nothing of roots" do
      watched = insert(:source)
      insert(:source, enabled: false)
      insert(:root)

      assert Library.watched_sources() |> Enum.map(& &1.id) == [watched.id]
    end
  end

  describe "deleting" do
    test "removes the source row and leaves its files alone" do
      dir = tmp_dir()
      file = Path.join(dir, "keep.txt")
      File.write!(file, "still here")
      source = insert(:source, path: dir)

      assert {:ok, _source} = Library.delete_source(source)
      assert {:error, :not_found} = Library.fetch_source(source.id)
      assert File.exists?(file)
    end

    test "removes the root row and leaves its files alone" do
      dir = tmp_dir()
      file = Path.join(dir, "keep.txt")
      File.write!(file, "still here")
      root = insert(:root, path: dir)

      assert {:ok, _root} = Library.delete_root(root)
      assert {:error, :not_found} = Library.fetch_root(root.id)
      assert File.exists?(file)
    end
  end

  describe "mark_scanned/1" do
    test "stamps the scan time" do
      source = insert(:source, last_scanned_at: nil)

      assert {:ok, source} = Library.mark_scanned(source)
      assert %DateTime{} = source.last_scanned_at
    end
  end

  describe "status/1" do
    test "reports a real folder" do
      status = Library.status(tmp_dir())

      assert status.exists?
      assert status.directory?
      assert status.writable?
      assert is_integer(status.device)
    end

    test "reports a file as existing but not a folder" do
      file = Path.join(tmp_dir(), "a-file")
      File.write!(file, "")

      status = Library.status(file)

      assert status.exists?
      refute status.directory?
    end

    # An unmounted NAS is the common case here, and it has to read as
    # "couldn't look", not as an empty folder.
    test "reports a missing path without a device" do
      status = Library.status("/definitely/not/here")

      refute status.exists?
      refute status.directory?
      assert is_nil(status.device)
    end
  end

  describe "the mount table" do
    alias Ambry.Library.Mounts

    # A realistic mountinfo excerpt: a root mount, a NAS export mounted
    # twice (one superblock — same 0:70 — two mounts), a mount point with an
    # escaped space, and an overmount shadowing /mnt/old.
    @mountinfo """
    40 1 0:34 /@ / rw,relatime shared:1 - btrfs /dev/nvme0n1p2 rw
    91 40 0:70 / /mnt/nas-a rw,relatime shared:401 - nfs4 nas:/export rw
    92 40 0:70 / /mnt/nas-b rw,relatime shared:402 - nfs4 nas:/export rw
    93 40 0:71 / /mnt/my\\040nas rw,relatime shared:403 - nfs4 nas2:/export rw
    94 40 0:72 / /mnt/old rw shared:404 - ext4 /dev/sdb1 rw
    95 40 0:73 / /mnt/old rw shared:405 - ext4 /dev/sdc1 rw
    """

    test "parses ids and unescapes mount points" do
      mounts = Mounts.parse(@mountinfo)

      assert %{id: 40, mount_point: "/"} in mounts
      assert %{id: 93, mount_point: "/mnt/my nas"} in mounts
    end

    test "matches the longest mount point on a segment boundary" do
      mounts = Mounts.parse(@mountinfo)

      assert {:ok, %{id: 91}} = Mounts.mount_of("/mnt/nas-a/downloads/book.m4b", mounts)
      # /mnt/nas-a is not a prefix of /mnt/nas-abc
      assert {:ok, %{id: 40}} = Mounts.mount_of("/mnt/nas-abc/file", mounts)
      assert {:ok, %{id: 40}} = Mounts.mount_of("/home/x", mounts)
    end

    test "an overmount shadows the mount it covers" do
      mounts = Mounts.parse(@mountinfo)

      assert {:ok, %{id: 95}} = Mounts.mount_of("/mnt/old/file", mounts)
    end

    # The case this module exists for: one NFS export mounted twice is one
    # superblock (one st_dev) and two mounts, and link(2) refuses across
    # them — so the two sides of the export must never share a mount id.
    test "two mounts of one export are two different mounts" do
      mounts = Mounts.parse(@mountinfo)

      assert {:ok, %{id: a}} = Mounts.mount_of("/mnt/nas-a/downloads", mounts)
      assert {:ok, %{id: b}} = Mounts.mount_of("/mnt/nas-b/library", mounts)
      refute a == b
    end
  end

  # A real second filesystem, found at compile time — same trick as
  # PlacementTest, so the refusal is exercised against the kernel.
  @other_filesystem Enum.find(["/dev/shm", "/tmp"], fn candidate ->
                      with true <- File.dir?(candidate),
                           {:ok, %{major_device: theirs}} <- File.stat(candidate),
                           {:ok, %{major_device: ours}} <- File.stat(File.cwd!()) do
                        theirs != ours
                      else
                        _unusable -> false
                      end
                    end)

  describe "same_filesystem?/2" do
    test "two paths on the same filesystem and mount" do
      dir = tmp_dir()
      assert {:ok, true} = Library.same_filesystem?(dir, tmp_dir())
      assert {:ok, true} = Library.same_filesystem?(dir, dir)
    end

    if @other_filesystem do
      test "two paths on different filesystems" do
        assert {:ok, false} = Library.same_filesystem?(tmp_dir(), @other_filesystem)
      end
    end

    # A missing mount must never read as "different filesystem", because the
    # caller's fallback for that is to copy — which is the storage doubling
    # this whole phase exists to prevent. It must not read as "same" either:
    # the only honest answer is that nobody knows.
    test "refuses to answer when a path can't be reached" do
      dir = tmp_dir()

      assert {:error, {:enoent, "/mnt/not-mounted"}} =
               Library.same_filesystem?(dir, "/mnt/not-mounted")

      assert {:error, {:enoent, _path}} = Library.device("/mnt/not-mounted/library/Author")
    end

    # The tempting shortcut — walk up to the nearest existing ancestor so a
    # not-yet-created destination can be asked about — is what makes an
    # unmounted volume answer confidently and wrongly. `/mnt` exists on the
    # root filesystem whether or not anything is mounted under it.
    test "does not answer for a nested path by falling back to its parent" do
      assert {:error, {:enoent, _path}} = Library.device("/mnt/not-mounted/nested/deeper")
    end
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("library-test-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
