defmodule Ambry.LibraryTest do
  use Ambry.DataCase

  alias Ambry.Library
  alias Ambry.Library.Location

  describe "create_location/1" do
    test "creates a downloads location" do
      assert {:ok, %Location{} = location} =
               Library.create_location(%{
                 name: "Downloads",
                 path: "/data/downloads",
                 kind: :downloads
               })

      assert location.path == "/data/downloads"
      assert location.kind == :downloads
      assert location.enabled
      assert is_nil(location.last_scanned_at)
    end

    test "defaults a downloads location to hardlinking" do
      assert {:ok, location} =
               Library.create_location(%{name: "D", path: "/data/d", kind: :downloads})

      assert location.import_policy == :hardlink
    end

    test "keeps an explicit import policy" do
      assert {:ok, location} =
               Library.create_location(%{
                 name: "D",
                 path: "/data/d",
                 kind: :downloads,
                 import_policy: :move
               })

      assert location.import_policy == :move
    end

    # The other kinds don't import from anywhere, so carrying a policy would
    # only ever mislead whoever reads the row later.
    test "clears the import policy for kinds that don't import" do
      for kind <- [:external_collection, :library_root] do
        assert {:ok, location} =
                 Library.create_location(%{
                   name: "L #{kind}",
                   path: "/data/#{kind}",
                   kind: kind,
                   import_policy: :hardlink
                 })

        assert is_nil(location.import_policy)
      end
    end

    test "requires an absolute path" do
      assert {:error, changeset} =
               Library.create_location(%{name: "D", path: "relative/path", kind: :downloads})

      assert "must be an absolute path" in errors_on(changeset).path
    end

    test "normalizes surrounding whitespace and a trailing slash" do
      assert {:ok, location} =
               Library.create_location(%{
                 name: "D",
                 path: "  /data/downloads/  ",
                 kind: :downloads
               })

      assert location.path == "/data/downloads"
    end

    test "keeps the root path intact" do
      assert {:ok, location} =
               Library.create_location(%{name: "R", path: "/", kind: :library_root})

      assert location.path == "/"
    end

    test "refuses a duplicate path" do
      insert(:location, path: "/data/downloads")

      assert {:error, changeset} =
               Library.create_location(%{
                 name: "Other",
                 path: "/data/downloads",
                 kind: :downloads
               })

      assert "has already been taken" in errors_on(changeset).path
    end

    test "refuses a duplicate name" do
      insert(:location, name: "Downloads")

      assert {:error, changeset} =
               Library.create_location(%{
                 name: "Downloads",
                 path: "/data/other",
                 kind: :downloads
               })

      assert "has already been taken" in errors_on(changeset).name
    end
  end

  describe "list_locations/1" do
    test "filters by kind and by enabled" do
      downloads = insert(:location, kind: :downloads)
      root = insert(:location, kind: :library_root, import_policy: nil)
      paused = insert(:location, kind: :downloads, enabled: false)

      assert Library.list_locations() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([downloads.id, root.id, paused.id])

      assert Library.library_roots() |> Enum.map(& &1.id) == [root.id]

      assert Library.list_locations(enabled: true) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([downloads.id, root.id])
    end

    # Library roots are watched too — that's how a file dropped straight into
    # the tree gets noticed instead of sitting there unknown.
    test "watched locations include library roots and exclude paused ones" do
      root = insert(:location, kind: :library_root, import_policy: nil)
      insert(:location, kind: :downloads, enabled: false)

      assert Library.watched_locations() |> Enum.map(& &1.id) == [root.id]
    end
  end

  describe "delete_location/1" do
    test "removes the row and leaves the files alone" do
      dir = tmp_dir()
      file = Path.join(dir, "keep.txt")
      File.write!(file, "still here")
      location = insert(:location, path: dir)

      assert {:ok, _location} = Library.delete_location(location)
      assert {:error, :not_found} = Library.fetch_location(location.id)
      assert File.exists?(file)
    end
  end

  describe "mark_scanned/1" do
    test "stamps the scan time" do
      location = insert(:location, last_scanned_at: nil)

      assert {:ok, location} = Library.mark_scanned(location)
      assert %DateTime{} = location.last_scanned_at
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
