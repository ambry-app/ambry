defmodule Ambry.InboxTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem

  describe "discover/1" do
    test "offers each release folder as one candidate" do
      root = watched_root()
      release = release_folder(root, "The Way of Kings [M4B]", ["book.m4b"])

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      assert {[%InboxItem{} = item], false} = Inbox.list_items()
      assert item.path == release
      assert item.files == [Path.join(release, "book.m4b")]
      assert item.status == :pending
    end

    test "offers a loose file as its own candidate" do
      root = watched_root()
      loose = copy_audio(root, "Project Hail Mary.m4b")

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.path == loose
      assert item.files == [loose]
    end

    test "finds audio nested inside a release folder" do
      root = watched_root()
      release = Path.join(root, "Some Release")
      nested = Path.join(release, "Disc 1")
      File.mkdir_p!(nested)
      copy_audio(nested, "01.mp3")

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.path == release
      assert [file] = item.files
      assert file =~ "Disc 1/01.mp3"
    end

    test "keeps a multi-file release as one candidate" do
      root = watched_root()
      release = release_folder(root, "Chaptered Book", ["01.mp3", "02.mp3", "03.mp3"])

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.path == release
      assert length(item.files) == 3
    end

    # Release names are full of glob metacharacters, and a folder that goes
    # missing because of one is invisible rather than noisy.
    test "finds releases whose names contain glob characters" do
      root = watched_root()

      for name <- ["Book [M4B] {64kbps}", "What Is It? (2020)", "Star * Wars"] do
        release_folder(root, name, ["book.m4b"])
      end

      assert {:ok, %{created: 3}} = Inbox.discover(root)
    end

    test "ignores folders with no audio in them" do
      root = watched_root()
      junk = Path.join(root, "Artwork")
      File.mkdir_p!(junk)
      File.write!(Path.join(junk, "cover.jpg"), "not audio")
      File.write!(Path.join(root, "readme.txt"), "not audio")

      assert {:ok, %{created: 0}} = Inbox.discover(root)
      assert {[], false} = Inbox.list_items()
    end

    test "reports a watched location that isn't there" do
      assert {:error, :watched_location_missing} = Inbox.discover("/nope/not/here")
    end
  end

  describe "discover/1 idempotency" do
    test "rescanning doesn't duplicate what it already offered" do
      root = watched_root()
      release_folder(root, "A Book", ["book.m4b"])

      assert {:ok, %{created: 1}} = Inbox.discover(root)
      assert {:ok, %{created: 0, skipped: 1}} = Inbox.discover(root)

      assert {[_one], false} = Inbox.list_items()
    end

    test "never resurrects something dismissed" do
      root = watched_root()
      release_folder(root, "Not Wanted", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.dismiss_item(item)

      assert {:ok, %{created: 0}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :dismissed
    end

    test "picks up files that appeared after the first look" do
      root = watched_root()
      release = release_folder(root, "Growing Set", ["01.mp3"])
      {:ok, _counts} = Inbox.discover(root)

      copy_audio(release, "02.mp3")

      assert {:ok, %{updated: 1}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert length(item.files) == 2
    end

    test "leaves a dismissed item dismissed even when its files change" do
      root = watched_root()
      release = release_folder(root, "Growing Set", ["01.mp3"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.dismiss_item(item)

      copy_audio(release, "02.mp3")
      {:ok, _counts} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :dismissed
      assert length(item.files) == 2
    end
  end

  describe "discover/1 and the existing library" do
    test "doesn't offer files the library already has as direct-play tracks" do
      root = watched_root()
      release = release_folder(root, "Already Imported", ["book.m4b"])

      media = insert(:media, book: build(:book))
      insert(:media_track, media: media, path: Path.join(release, "book.m4b"))

      assert {:ok, %{created: 0, skipped: 1}} = Inbox.discover(root)
      assert {[], false} = Inbox.list_items()
    end

    test "doesn't offer files a legacy media was imported from" do
      root = watched_root()
      release = release_folder(root, "Already Imported", ["book.m4b"])

      insert(:media, book: build(:book), source_files: [Path.join(release, "book.m4b")])

      assert {:ok, %{created: 0, skipped: 1}} = Inbox.discover(root)
      assert {[], false} = Inbox.list_items()
    end
  end

  describe "probe_item/1" do
    test "records what the file is and what it claims about itself" do
      root = watched_root()
      release = release_folder(root, "Tagged Book", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.probe_item(item)

      refute item.issue
      assert item.probe["codec"] == "aac"
      assert item.probe["mime"] == "audio/mp4"
      assert item.probe["seek_accuracy"] == "exact"
      assert item.probe["path"] == Path.join(release, "book.m4b")
      assert is_map(item.tags)
    end

    test "flags a multi-file release instead of hiding it" do
      root = watched_root()
      release_folder(root, "Chaptered Book", ["01.mp3", "02.mp3"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.probe_item(item)

      assert item.issue =~ "2 audio files"
      assert item.status == :pending
      # still probed, so the operator has something to look at
      assert item.probe["codec"] == "mp3"
    end

    @tag :capture_log
    test "keeps an unreadable candidate in the queue with a reason" do
      root = watched_root()
      release = Path.join(root, "Broken")
      File.mkdir_p!(release)
      File.write!(Path.join(release, "book.m4b"), "this is not audio")
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.probe_item(item)

      assert item.issue =~ "couldn't read the file"
      assert item.status == :pending
    end
  end

  describe "dismiss_item/1 and restore_item/1" do
    test "take an item out of the queue and back, without touching files" do
      root = watched_root()
      release = release_folder(root, "A Book", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      {:ok, item} = Inbox.dismiss_item(item)
      assert item.status == :dismissed
      assert File.exists?(Path.join(release, "book.m4b"))

      {:ok, item} = Inbox.restore_item(item)
      assert item.status == :pending
    end
  end

  describe "list_items/1" do
    test "filters by status and path" do
      root = watched_root()
      release_folder(root, "Keeper", ["book.m4b"])
      release_folder(root, "Reject", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      reject = Enum.find(items, &(InboxItem.name(&1) == "Reject"))
      {:ok, _item} = Inbox.dismiss_item(reject)

      assert {[item], false} = Inbox.list_items(status: :pending)
      assert InboxItem.name(item) == "Keeper"

      assert {[item], false} = Inbox.list_items(filter: "Reject")
      assert InboxItem.name(item) == "Reject"

      assert %{pending: 1, dismissed: 1} = Inbox.count_by_status()
    end
  end

  # Nothing in the inbox may modify what it finds, so every test works
  # against a real throwaway tree of real audio files.
  defp watched_root do
    root = Ambry.Paths.source_media_disk_path("watched-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    root
  end

  defp release_folder(root, name, filenames) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    Enum.each(filenames, &copy_audio(dir, &1))
    dir
  end

  defp copy_audio(dir, filename) do
    fixture =
      case Path.extname(filename) do
        ".mp3" -> valid_audio(:mp3)
        _m4b -> valid_audio(:m4a)
      end

    dest = Path.join(dir, filename)
    File.cp!(fixture, dest)
    dest
  end
end
