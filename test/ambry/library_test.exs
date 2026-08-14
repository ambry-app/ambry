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

  describe "same_filesystem?/2" do
    test "two paths on the same filesystem" do
      dir = tmp_dir()
      assert {:ok, true} = Library.same_filesystem?(dir, tmp_dir())
      assert {:ok, true} = Library.same_filesystem?(dir, dir)
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
