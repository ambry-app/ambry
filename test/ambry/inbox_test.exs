defmodule Ambry.InboxTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem
  alias Ambry.Media.Scanner

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

  # The safety property the whole mechanism is built on, stated where it can
  # be broken: **a scan may not change who owns a file.** It creates items
  # from files nothing owns, adds unowned files to the item that owns their
  # folder, and drops files that are gone. Nothing else.
  # Two grains that produce the same items are one grain wearing two hats,
  # and the form should not ask the operator to choose between them.
  describe "split_grains/1" do
    test "offers the finer grain only when it divides further" do
      root = watched_root()

      set = Path.join(root, "The Way of Kings")
      for part <- ["1 of 2", "2 of 2"], do: release_folder(set, part, ["01.mp3", "02.mp3"])

      series = Path.join(root, "Zones of Thought")

      for title <- ["A Fire Upon the Deep", "A Deepness in the Sky"],
          do: release_folder(series, title, ["book.m4b"])

      copy_audio(series, "stray.mp3")

      pair = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])

      {:ok, _counts} = Inbox.discover(root)
      {items, false} = Inbox.list_items()
      grains = Map.new(items, &{&1.path, Inbox.split_grains(&1)})

      # parts of several files each: both grains say something different
      assert grains[set] == %{folder: 2, file: 4}

      # three folders of one file each plus a stray: the folder grain wins,
      # and the file grain would produce the same four items
      assert grains[series] == %{folder: 3}

      # one folder, so only the finest grain divides anything
      assert grains[pair] == %{file: 2}
    end
  end

  describe "discover/1 ownership" do
    test "a file already owned is never re-grouped, however the walk sees it" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      # the operator says these are two books, at the finest grain
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item, :file)

      # the walk still sees one folder holding two files, and is not asked
      assert {:ok, %{created: 0, updated: 0}} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 2

      assert items |> Enum.flat_map(& &1.files) |> Enum.sort() ==
               [Path.join(release, "one.m4b"), Path.join(release, "two.m4b")]
    end

    test "a folder split keeps each part's files, and the leftovers" do
      root = watched_root()
      book = Path.join(root, "The Way of Kings")
      for part <- ["1 of 2", "2 of 2"], do: release_folder(book, part, ["01.mp3", "02.mp3"])
      copy_audio(book, "stray.mp3")

      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      assert length(item.files) == 5

      {:ok, _children} = Inbox.split_item(item, :folder)
      before = ownership()

      assert {:ok, %{created: 0, updated: 0}} = Inbox.discover(root)
      assert ownership() == before
    end

    test "an imported item is never touched, even when its files have moved" do
      root = watched_root()
      release = release_folder(root, "Already Mine", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, item} = Inbox.update_item(item, %{status: :imported})

      # a managed import moves the bytes out of the downloads folder
      File.rm_rf!(release)
      File.mkdir_p!(release)

      assert {:ok, %{updated: 0}} = Inbox.discover(root)

      assert %{status: :imported, files: files} = Inbox.get_item!(item.id)
      assert files == item.files
    end

    test "a new file joins the item that owns its folder, rather than starting one" do
      root = watched_root()
      release = release_folder(root, "Growing Release", ["01.mp3"])
      {:ok, _counts} = Inbox.discover(root)

      copy_audio(release, "02.mp3")

      assert {:ok, %{created: 0, updated: 1}} = Inbox.discover(root)
      assert {[item], false} = Inbox.list_items()
      assert length(item.files) == 2
    end

    test "a new file in a folder the operator took apart becomes its own item" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item, :file)

      copy_audio(release, "three.m4b")

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 3
      assert Enum.all?(items, &(length(&1.files) == 1))
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

    test "measures a multi-file release as the one recording it will become" do
      root = watched_root()
      release_folder(root, "Chaptered Book", ["01.mp3", "02.mp3"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.probe_item(item)

      refute item.issue
      assert item.probe["files"] == 2
      assert item.probe["codec"] == "mp3"

      # The rows themselves, not just the count — the import form's chapter
      # editor states what the files carry without re-reading them.
      assert item.probe["chapters"] == 2
      assert item.probe["chapter_marker_source"] == "file_boundaries"

      assert [%{"time" => _start, "title" => _first, "title_source" => _source}, %{}] =
               item.probe["chapter_list"]

      # The whole book, not the first file: the durations add up into one
      # timeline, and so do the bytes.
      {:ok, one} = Scanner.probe_file(Path.join(item.path, "01.mp3"))
      assert Decimal.equal?(Decimal.new(item.probe["duration"]), Decimal.mult(one.duration, 2))
      assert item.probe["size"] == one.size * 2
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

  describe "prepare_draft/1 destination healing" do
    # A destination's defaults are derived from the item's source, so healing
    # fills gaps without un-answering anything. The gap: an ad-hoc-scanned
    # item adopts its source when that source's own scan next sees it, and a
    # draft sealed without a policy now has one on offer.
    test "fills in the policy when the item adopts a source after drafting" do
      dir = watched_root()
      release_folder(dir, "Sourced Later", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(dir)
      {[item], false} = Inbox.list_items(filter: "Sourced Later")
      {:ok, item} = Inbox.probe_item(item)

      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.destination.policy == nil
      refute item.draft.destination.approved

      source = insert(:source, path: dir, import_policy: :copy)
      root = insert(:root)
      item = item |> Ecto.Changeset.change(source_id: source.id) |> Repo.update!()

      {:ok, healed} = Inbox.prepare_draft(Inbox.get_item!(item.id))

      assert healed.draft.destination.policy == :copy
      # the single root auto-picks, exactly as a fresh seed would
      assert healed.draft.destination.root_id == root.id
      assert healed.draft.destination.approved
    end

    test "a settled destination is left alone" do
      dir = watched_root()
      release_folder(dir, "Stays Settled", ["book.m4b"])
      insert(:source, path: dir, import_policy: :copy)
      insert(:root)
      {:ok, _counts} = Inbox.discover()
      {[item], false} = Inbox.list_items(filter: "Stays Settled")
      {:ok, item} = Inbox.probe_item(item)

      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.destination.approved

      {:ok, again} = Inbox.prepare_draft(Inbox.get_item!(item.id))

      assert again.draft.destination == item.draft.destination
    end
  end

  describe "root blockers" do
    # "No root chosen" and "no root exists" are different problems with
    # different fixes — the picker sits right above the message.
    test "an unpicked root among several says pick one, not none" do
      dir = watched_root()
      release_folder(dir, "Which Root", ["book.m4b"])
      insert(:source, path: dir)
      insert(:root)
      insert(:root)

      {:ok, _counts} = Inbox.discover()
      {[item], false} = Inbox.list_items(filter: "Which Root")
      {:ok, item} = Inbox.probe_item(item)
      {:ok, item} = Inbox.prepare_draft(item)

      preflight = Inbox.destination_preflight(item)
      assert preflight.blocker =~ "more than one library root"
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

    test "the queue is newest-found first" do
      root = watched_root()
      release_folder(root, "Found first", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      release_folder(root, "Found second", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      assert {items, false} = Inbox.list_items(status: :pending)
      assert Enum.map(items, &InboxItem.name/1) == ["Found second", "Found first"]
    end

    # The queue and the history run on two different clocks. Sorting the
    # history by discovery time is what buried a release imported this
    # morning under one imported last week.
    test "the history is most-recently-acted-on first, not newest-found" do
      root = watched_root()
      release_folder(root, "Found first", ["book.m4b"])
      release_folder(root, "Found second", ["book.m4b"])
      {:ok, _counts} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      first = Enum.find(items, &(InboxItem.name(&1) == "Found first"))
      second = Enum.find(items, &(InboxItem.name(&1) == "Found second"))

      # Acted on in the opposite order to the one they were found in.
      {:ok, _item} = Inbox.ignore_item(second)
      # `updated_at` has second resolution, so without this both rows carry
      # the same timestamp and the tie-break decides — which would pass for
      # the wrong reason.
      Process.sleep(1100)
      {:ok, _item} = Inbox.ignore_item(first)

      assert {items, false} = Inbox.list_items(status: :ignored)
      assert Enum.map(items, &InboxItem.name/1) == ["Found first", "Found second"]
    end
  end

  describe "discover/0 across registered sources" do
    test "refuses to guess when nothing is registered" do
      assert {:error, :no_watched_sources} = Inbox.discover()
    end

    test "scans every enabled source and records where each item came from" do
      downloads = insert(:source, path: watched_root())

      collection =
        insert(:source, path: watched_root(), import_policy: :symlink)

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

  # The grouping heuristic's known failure: two unrelated single-file books
  # sharing a folder become one 2-file item, which multi-file support being
  # deferred makes unimportable. Split is the operator's correction, and it
  # has to survive the hourly rescan or it silently un-happens.
  describe "split_item/1" do
    test "splits a folder of separate books into one item per file" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      assert {:ok, %{created: 1}} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, children} = Inbox.split_item(item)

      assert Enum.sort(Enum.map(children, & &1.path)) ==
               Enum.sort([Path.join(release, "one.m4b"), Path.join(release, "two.m4b")])

      assert Enum.all?(children, &(&1.files == [&1.path]))
      refute Repo.get(InboxItem, item.id)

      # each child probes (and then matches) fresh — the parent's probe and
      # tags described its first file only
      for child <- children do
        assert_enqueued(worker: Ambry.Inbox.RunProbe, args: %{inbox_item_id: child.id})
      end
    end

    test "a rescan respects the split instead of re-merging the folder" do
      root = watched_root()
      release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item)

      assert {:ok, %{created: 0}} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 2
      assert Enum.all?(items, &(length(&1.files) == 1))
    end

    test "a file that appears in a split folder becomes its own item" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = Inbox.discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item)

      copy_audio(release, "three.m4b")

      assert {:ok, %{created: 1}} = Inbox.discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 3
      assert Enum.any?(items, &(&1.path == Path.join(release, "three.m4b")))
    end

    test "refuses an imported item and a single-file item" do
      imported = raw_item(%{path: "/two", files: ["/a.m4b", "/b.m4b"], status: :imported})
      assert {:error, :already_imported} = Inbox.split_item(imported)

      single = raw_item(%{path: "/only.m4b", files: ["/only.m4b"]})
      assert {:error, :not_multi_file} = Inbox.split_item(single)
    end
  end

  defp raw_item(attrs) do
    %InboxItem{} |> InboxItem.changeset(attrs) |> Repo.insert!()
  end

  # Nothing in the inbox may modify what it finds, so every test works
  # against a real throwaway tree of real audio files.
  # Who owns what, as the property tests compare it.
  defp ownership do
    {items, _more} = Inbox.list_items()
    for item <- items, file <- item.files, into: %{}, do: {file, item.path}
  end

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
