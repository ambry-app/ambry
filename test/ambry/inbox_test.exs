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

    # Every shape below is copied from the operator's real downloads folder,
    # where the naive "one candidate per immediate child" rule turned a
    # 43-book series into a single 1707-file item.
    test "splits a series folder into one candidate per book" do
      root = watched_root()
      series = Path.join(root, "Discworld")

      for title <- ["Discworld 5 Sourcery", "Discworld 30 The Wee Free Men", "Discworld 39 Snuff"] do
        release_folder(series, title, ["book.m4b"])
      end

      assert {:ok, %{created: 3}} = Inbox.discover(root)

      {items, false} = Inbox.list_items()

      assert Enum.map(items, &InboxItem.name/1) |> Enum.sort() == [
               "Discworld 30 The Wee Free Men",
               "Discworld 39 Snuff",
               "Discworld 5 Sourcery"
             ]
    end

    test "keeps a book split across numbered part folders as one candidate" do
      root = watched_root()
      book = Path.join(root, "1 The Way of Kings")

      for part <- ["1 of 5", "2 of 5", "3 of 5"] do
        release_folder(book, part, ["01.mp3", "02.mp3"])
      end

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      assert InboxItem.name(item) == "1 The Way of Kings"
      assert length(item.files) == 6
    end

    test "keeps a book split across disc folders as one candidate" do
      root = watched_root()
      book = Path.join(root, "The Colorado Kid by Stephen King")

      for disc <- ["The Colorado Kid (Disc 01)", "The Colorado Kid (Disc 02)"] do
        release_folder(book, disc, ["01.mp3"])
      end

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      assert InboxItem.name(item) == "The Colorado Kid by Stephen King"
      assert length(item.files) == 2
    end

    # The trap in the other direction: these look part-ish because they end
    # in a number, but they're three separate books.
    test "does not merge separately numbered books into one candidate" do
      root = watched_root()
      trilogy = Path.join(root, "Gwendy's Button Box")

      for book <- ["Gwendy's Button Box 1", "Gwendy's Button Box 2", "Gwendy's Button Box 3"] do
        release_folder(trilogy, book, ["book.m4b"])
      end

      assert {:ok, %{created: 3}} = Inbox.discover(root)
    end

    test "looks inside an author folder holding a single book" do
      root = watched_root()
      author = Path.join(root, "Dennis E. Taylor")
      release_folder(author, "Book 5 - Not Till We Are Lost", ["book.m4b"])

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      assert InboxItem.name(item) == "Book 5 - Not Till We Are Lost"
    end

    test "treats a folder holding audio directly as the release, subfolders or not" do
      root = watched_root()
      release = release_folder(root, "Dan Brown - Origin", ["01.mp3", "02.mp3"])
      extras = Path.join(release, "extras")
      File.mkdir_p!(extras)
      copy_audio(extras, "interview.mp3")

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      assert InboxItem.name(item) == "Dan Brown - Origin"
      assert length(item.files) == 3
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
      assert {:error, :watched_source_missing} = Inbox.discover("/nope/not/here")
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

    test "never resurrects something ignored" do
      root = watched_root()
      release_folder(root, "Not Wanted", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.ignore_item(item)

      assert {:ok, %{created: 0}} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :ignored
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

    test "leaves an ignored item ignored even when its files change" do
      root = watched_root()
      release = release_folder(root, "Growing Set", ["01.mp3"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.ignore_item(item)

      copy_audio(release, "02.mp3")
      {:ok, _counts} = Inbox.discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :ignored
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

  describe "ignore_item/1 and restore_item/1" do
    test "take an item out of the queue and back, without touching files" do
      root = watched_root()
      release = release_folder(root, "A Book", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      {:ok, item} = Inbox.ignore_item(item)
      assert item.status == :ignored
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
      {:ok, _item} = Inbox.ignore_item(reject)

      assert {[item], false} = Inbox.list_items(status: :pending)
      assert InboxItem.name(item) == "Keeper"

      assert {[item], false} = Inbox.list_items(filter: "Reject")
      assert InboxItem.name(item) == "Reject"

      assert %{pending: 1, ignored: 1} = Inbox.count_by_status()
    end
  end

  describe "discover/0 across registered sources" do
    test "refuses to guess when nothing is registered" do
      assert {:error, :no_watched_sources} = Inbox.discover()
    end

    test "scans every enabled source and records where each item came from" do
      downloads = insert(:source, path: watched_root())

      collection =
        insert(:source, path: watched_root(), on_import: :leave_in_place, import_policy: nil)

      release_folder(downloads.path, "Leviathan Wakes", ["book.m4b"])
      release_folder(collection.path, "Project Hail Mary", ["book.m4b"])

      assert {:ok, %{created: 2, unreachable: 0}} = Inbox.discover()

      {items, false} = Inbox.list_items()

      assert Enum.map(items, & &1.source_id) |> Enum.sort() ==
               Enum.sort([downloads.id, collection.id])
    end

    test "skips paused sources" do
      paused = insert(:source, path: watched_root(), enabled: false)
      release_folder(paused.path, "Leviathan Wakes", ["book.m4b"])

      assert {:error, :no_watched_sources} = Inbox.discover()
      assert {[], false} = Inbox.list_items()
    end

    # One unmounted NAS must not stop the others from being scanned, but it
    # also must not read as "nothing new here".
    @tag :capture_log
    test "counts an unreachable source without failing the run" do
      good = insert(:source, path: watched_root())
      insert(:source, path: "/mnt/not-mounted")
      release_folder(good.path, "Leviathan Wakes", ["book.m4b"])

      assert {:ok, %{created: 1, unreachable: 1}} = Inbox.discover()
    end

    test "stamps the scan time on sources it reached" do
      source = insert(:source, path: watched_root(), last_scanned_at: nil)

      assert {:ok, _counts} = Inbox.discover()
      assert %DateTime{} = Ambry.Library.get_source!(source.id).last_scanned_at
    end

    # An item found under a source adopts it: that's a fact the scan just
    # established, not a guess about an item whose origin was never known.
    test "backfills the source of an item discovered before sources existed" do
      root = watched_root()
      release = release_folder(root, "Leviathan Wakes", ["book.m4b"])

      assert {:ok, %{created: 1}} = Inbox.discover(root)
      assert {[item], false} = Inbox.list_items()
      assert is_nil(item.source_id)

      source = insert(:source, path: root)

      assert {:ok, %{updated: 1}} = Inbox.discover()
      assert {[item], false} = Inbox.list_items()
      assert item.path == release
      assert item.source_id == source.id
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
