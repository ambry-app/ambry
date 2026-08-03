defmodule Ambry.Library.PlacementTest do
  use ExUnit.Case, async: true

  alias Ambry.Library.Placement

  # A real second filesystem, found at compile time, so the cross-filesystem
  # behaviour is exercised against the actual kernel rather than a mock.
  # `/dev/shm` is tmpfs and therefore always a different device from the
  # project checkout; if a machine somehow has neither candidate, the
  # cross-filesystem tests are omitted rather than silently passing.
  @other_filesystem Enum.find(["/dev/shm", "/tmp"], fn candidate ->
                      with true <- File.dir?(candidate),
                           {:ok, %{major_device: theirs}} <- File.stat(candidate),
                           {:ok, %{major_device: ours}} <- File.stat(File.cwd!()) do
                        theirs != ours
                      else
                        _unusable -> false
                      end
                    end)

  setup do
    root = tmp_dir("placement")
    source_dir = tmp_dir("source")
    source = Path.join(source_dir, "book.m4b")
    File.write!(source, "audio bytes")

    on_exit(fn ->
      File.rm_rf(root)
      File.rm_rf(source_dir)
    end)

    %{root: root, source: source}
  end

  describe "hardlink" do
    test "links into the library without using more space", %{root: root, source: source} do
      destination = Path.join([root, "Author", "Title", "Title.m4b"])

      assert {:ok, placement} = Placement.place(source, destination, :hardlink)
      assert placement.policy == :hardlink

      assert File.read!(destination) == "audio bytes"
      # the source keeps seeding
      assert File.exists?(source)
      # one inode, two names
      assert {:ok, %{links: 2}} = File.stat(destination)
      assert inode(destination) == inode(source)
    end

    test "creates the intermediate folders", %{root: root, source: source} do
      destination = Path.join([root, "A", "B", "C", "Title.m4b"])

      assert {:ok, _placement} = Placement.place(source, destination, :hardlink)
      assert File.dir?(Path.join([root, "A", "B"]))
    end

    if @other_filesystem do
      # The silent fallback — copy when a link isn't possible — is exactly the
      # storage doubling this phase exists to eliminate, and the operator
      # would have no way to know it happened.
      test "refuses across filesystems instead of quietly copying", %{source: source} do
        root = tmp_dir(Path.join(@other_filesystem, "ambry-placement"))
        on_exit(fn -> File.rm_rf(root) end)

        destination = Path.join([root, "Author", "Title.m4b"])

        assert {:error, {:cross_filesystem, ^source, ^destination}} =
                 Placement.place(source, destination, :hardlink)

        refute File.exists?(destination)
      end

      test "a move across filesystems falls back to copying, which is what a move is",
           %{source: source} do
        root = tmp_dir(Path.join(@other_filesystem, "ambry-placement"))
        on_exit(fn -> File.rm_rf(root) end)

        destination = Path.join([root, "Title.m4b"])

        assert {:ok, placement} = Placement.place(source, destination, :move)
        assert File.read!(destination) == "audio bytes"

        # still there until the database work commits
        assert File.exists?(source)
        assert :ok = Placement.finalize(placement)
        refute File.exists?(source)
      end
    end
  end

  describe "copy" do
    test "duplicates the file", %{root: root, source: source} do
      destination = Path.join(root, "Title.m4b")

      assert {:ok, _placement} = Placement.place(source, destination, :copy)
      assert File.read!(destination) == "audio bytes"
      assert File.exists?(source)
      assert inode(destination) != inode(source)
    end
  end

  describe "move" do
    # The source survives until the caller says the database committed. A
    # file moved before a failed commit is a file with no record pointing at
    # it and no source left to retry from.
    test "leaves the source alone until finalized", %{root: root, source: source} do
      destination = Path.join(root, "Title.m4b")

      assert {:ok, placement} = Placement.place(source, destination, :move)
      assert File.exists?(source)
      assert File.exists?(destination)

      assert :ok = Placement.finalize(placement)
      refute File.exists?(source)
      assert File.read!(destination) == "audio bytes"
    end

    test "undoing before finalize leaves the source untouched", %{root: root, source: source} do
      destination = Path.join([root, "Author", "Title.m4b"])

      assert {:ok, placement} = Placement.place(source, destination, :move)
      assert :ok = Placement.undo(placement)

      refute File.exists?(destination)
      assert File.read!(source) == "audio bytes"
    end
  end

  describe "refusals" do
    # Two recordings rendering to one path is a curation problem the operator
    # needs to see, not something to paper over with " (2)".
    test "never clobbers an existing file", %{root: root, source: source} do
      destination = Path.join(root, "Title.m4b")
      File.mkdir_p!(root)
      File.write!(destination, "something already here")

      assert {:error, {:destination_exists, ^destination}} =
               Placement.place(source, destination, :hardlink)

      assert File.read!(destination) == "something already here"
    end

    test "reports a source that vanished between discovery and approval", %{root: root} do
      missing = "/nope/not/here.m4b"

      assert {:error, {:source_missing, ^missing}} =
               Placement.place(missing, Path.join(root, "Title.m4b"), :copy)
    end

    test "reports a directory given where a file was expected", %{root: root, source: source} do
      assert {:error, {:source_missing, _path}} =
               Placement.place(Path.dirname(source), Path.join(root, "T.m4b"), :copy)
    end
  end

  describe "undo/1" do
    test "removes the file and the folders it created", %{root: root, source: source} do
      destination = Path.join([root, "Author", "Series", "Title.m4b"])

      assert {:ok, placement} = Placement.place(source, destination, :hardlink)
      assert :ok = Placement.undo(placement)

      refute File.exists?(destination)
      refute File.dir?(Path.join([root, "Author", "Series"]))
      refute File.dir?(Path.join([root, "Author"]))
    end

    # Pruning must stop at the first non-empty directory, or an undo could
    # walk up and remove the library root itself.
    test "stops pruning at a folder that still holds something", %{root: root, source: source} do
      keep = Path.join([root, "Author", "Other Book.m4b"])
      File.mkdir_p!(Path.dirname(keep))
      File.write!(keep, "another book")

      destination = Path.join([root, "Author", "Series", "Title.m4b"])
      assert {:ok, placement} = Placement.place(source, destination, :hardlink)
      assert :ok = Placement.undo(placement)

      refute File.dir?(Path.join([root, "Author", "Series"]))
      assert File.exists?(keep)
      assert File.dir?(root)
    end
  end

  defp tmp_dir(prefix) do
    dir = "#{prefix}-#{Ecto.UUID.generate()}"
    dir = if String.starts_with?(prefix, "/"), do: dir, else: Path.join(System.tmp_dir!(), dir)
    File.mkdir_p!(dir)
    dir
  end

  defp inode(path) do
    {:ok, %{inode: inode}} = File.stat(path)
    inode
  end
end
