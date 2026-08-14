defmodule Ambry.InboxTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library
  alias Ambry.Library.Source
  alias Ambry.Media.Scanner

  describe "discover/1" do
    test "offers each release folder as one candidate" do
      root = watched_root()
      release = release_folder(root, "The Way of Kings [M4B]", ["book.m4b"])

      assert {:ok, %{created: 1}} = discover(root)

      assert {[%InboxItem{} = item], false} = Inbox.list_items()
      assert InboxItem.disk_path(item) == release
      assert InboxItem.disk_files(item) == [Path.join(release, "book.m4b")]
      assert item.status == :pending
    end

    test "offers a loose file as its own candidate" do
      root = watched_root()
      loose = copy_audio(root, "Project Hail Mary.m4b")

      assert {:ok, %{created: 1}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert InboxItem.disk_path(item) == loose
      assert InboxItem.disk_files(item) == [loose]
    end

    test "finds audio nested inside a release folder" do
      root = watched_root()
      release = Path.join(root, "Some Release")
      nested = Path.join(release, "Disc 1")
      File.mkdir_p!(nested)
      copy_audio(nested, "01.mp3")

      assert {:ok, %{created: 1}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert InboxItem.disk_path(item) == release
      assert [file] = item.files
      assert file =~ "Disc 1/01.mp3"
    end

    test "keeps a multi-file release as one candidate" do
      root = watched_root()
      release = release_folder(root, "Chaptered Book", ["01.mp3", "02.mp3", "03.mp3"])

      assert {:ok, %{created: 1}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert InboxItem.disk_path(item) == release
      assert length(item.files) == 3
    end

    # Release names are full of glob metacharacters, and a folder that goes
    # missing because of one is invisible rather than noisy.
    test "finds releases whose names contain glob characters" do
      root = watched_root()

      for name <- ["Book [M4B] {64kbps}", "What Is It? (2020)", "Star * Wars"] do
        release_folder(root, name, ["book.m4b"])
      end

      assert {:ok, %{created: 3}} = discover(root)
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

      assert {:ok, %{created: 3}} = discover(root)

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

      assert {:ok, %{created: 1}} = discover(root)

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

      assert {:ok, %{created: 1}} = discover(root)

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

      assert {:ok, %{created: 3}} = discover(root)
    end

    test "looks inside an author folder holding a single book" do
      root = watched_root()
      author = Path.join(root, "Dennis E. Taylor")
      release_folder(author, "Book 5 - Not Till We Are Lost", ["book.m4b"])

      assert {:ok, %{created: 1}} = discover(root)

      {[item], false} = Inbox.list_items()
      assert InboxItem.name(item) == "Book 5 - Not Till We Are Lost"
    end

    test "treats a folder holding audio directly as the release, subfolders or not" do
      root = watched_root()
      release = release_folder(root, "Dan Brown - Origin", ["01.mp3", "02.mp3"])
      extras = Path.join(release, "extras")
      File.mkdir_p!(extras)
      copy_audio(extras, "interview.mp3")

      assert {:ok, %{created: 1}} = discover(root)

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

      assert {:ok, %{created: 0}} = discover(root)
      assert {[], false} = Inbox.list_items()
    end

    test "reports a watched location that isn't there" do
      assert {:error, :watched_source_missing} = discover("/nope/not/here")
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

      {:ok, _counts} = discover(root)
      {items, false} = Inbox.list_items()
      grains = Map.new(items, &{InboxItem.disk_path(&1), Inbox.split_grains(&1)})

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
      {:ok, _counts} = discover(root)

      # the operator says these are two books, at the finest grain
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item, :file)

      # the walk still sees one folder holding two files, and is not asked
      assert {:ok, %{created: 0, updated: 0}} = discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 2

      assert items |> Enum.flat_map(&InboxItem.disk_files/1) |> Enum.sort() ==
               [Path.join(release, "one.m4b"), Path.join(release, "two.m4b")]
    end

    test "a folder split keeps each part's files, and the leftovers" do
      root = watched_root()
      book = Path.join(root, "The Way of Kings")
      for part <- ["1 of 2", "2 of 2"], do: release_folder(book, part, ["01.mp3", "02.mp3"])
      copy_audio(book, "stray.mp3")

      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      assert length(item.files) == 5

      {:ok, _children} = Inbox.split_item(item, :folder)
      before = ownership()

      assert {:ok, %{created: 0, updated: 0}} = discover(root)
      assert ownership() == before
    end

    test "an imported item is never touched, even when its files have moved" do
      root = watched_root()
      release = release_folder(root, "Already Mine", ["book.m4b"])
      {:ok, _counts} = discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, item} = Inbox.update_item(item, %{status: :imported})

      # a managed import moves the bytes out of the downloads folder
      File.rm_rf!(release)
      File.mkdir_p!(release)

      assert {:ok, %{updated: 0}} = discover(root)

      assert %{status: :imported, files: files} = Inbox.get_item!(item.id)
      assert files == item.files
    end

    test "a new file joins the item that owns its folder, rather than starting one" do
      root = watched_root()
      release = release_folder(root, "Growing Release", ["01.mp3"])
      {:ok, _counts} = discover(root)

      copy_audio(release, "02.mp3")

      assert {:ok, %{created: 0, updated: 1}} = discover(root)
      assert {[item], false} = Inbox.list_items()
      assert length(item.files) == 2
    end

    test "a new file in a folder the operator took apart becomes its own item" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item, :file)

      copy_audio(release, "three.m4b")

      assert {:ok, %{created: 1}} = discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 3
      assert Enum.all?(items, &(length(&1.files) == 1))
    end
  end

  describe "discover/1 idempotency" do
    test "rescanning doesn't duplicate what it already offered" do
      root = watched_root()
      release_folder(root, "A Book", ["book.m4b"])

      assert {:ok, %{created: 1}} = discover(root)
      assert {:ok, %{created: 0, skipped: 1}} = discover(root)

      assert {[_one], false} = Inbox.list_items()
    end

    test "never resurrects something ignored" do
      root = watched_root()
      release_folder(root, "Not Wanted", ["book.m4b"])
      {:ok, _counts} = discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.ignore_item(item)

      assert {:ok, %{created: 0}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :ignored
    end

    test "picks up files that appeared after the first look" do
      root = watched_root()
      release = release_folder(root, "Growing Set", ["01.mp3"])
      {:ok, _counts} = discover(root)

      copy_audio(release, "02.mp3")

      assert {:ok, %{updated: 1}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert length(item.files) == 2
    end

    test "leaves an ignored item ignored even when its files change" do
      root = watched_root()
      release = release_folder(root, "Growing Set", ["01.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _item} = Inbox.ignore_item(item)

      copy_audio(release, "02.mp3")
      {:ok, _counts} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.status == :ignored
      assert length(item.files) == 2
    end
  end

  describe "discover/1 and the existing library" do
    # The scanned folder doubles as a registered root here — that's the one
    # arrangement where a scan can meet the library's own files, and the
    # comparison happens in {root, relative} coordinates.
    test "doesn't offer files the library already has as direct-play tracks" do
      root = watched_root()
      _release = release_folder(root, "Already Imported", ["book.m4b"])
      root_record = insert(:root, path: root)

      media =
        insert(:media,
          book: build(:book),
          library_root_id: root_record.id,
          source_path: "Already Imported"
        )

      insert(:media_track,
        media: media,
        path: "Already Imported/book.m4b",
        library_root_id: root_record.id
      )

      assert {:ok, %{created: 0, skipped: 1}} = discover(root)
      assert {[], false} = Inbox.list_items()
    end

    # A legacy recording's downloads provenance is quarantined in
    # `legacy_source_files`, and the ledger still honors it — otherwise every
    # pre-refactor import would resurface as new on the next scan.
    test "doesn't offer files a legacy media was imported from" do
      root = watched_root()
      release = release_folder(root, "Already Imported", ["book.m4b"])

      insert(:media, book: build(:book), legacy_source_files: [Path.join(release, "book.m4b")])

      assert {:ok, %{created: 0, skipped: 1}} = discover(root)
      assert {[], false} = Inbox.list_items()
    end
  end

  describe "probe_item/1" do
    test "records what the file is and what it claims about itself" do
      root = watched_root()
      release = release_folder(root, "Tagged Book", ["book.m4b"])
      {:ok, _counts} = discover(root)
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
      {:ok, _counts} = discover(root)
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
      {:ok, one} = Scanner.probe_file(Path.join(InboxItem.disk_path(item), "01.mp3"))
      assert Decimal.equal?(Decimal.new(item.probe["duration"]), Decimal.mult(one.duration, 2))
      assert item.probe["size"] == one.size * 2
    end

    @tag :capture_log
    test "keeps an unreadable candidate in the queue with a reason" do
      root = watched_root()
      release = Path.join(root, "Broken")
      File.mkdir_p!(release)
      File.write!(Path.join(release, "book.m4b"), "this is not audio")
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.probe_item(item)

      assert item.issue =~ "couldn't read the file"
      assert item.status == :pending
    end
  end

  # A draft is written once, at match time, and then only read. So a
  # destination nobody touched has to be re-derived rather than remembered,
  # or the first three hundred items queued behind a change keep proposing
  # what the default used to be.
  describe "prepare_draft/1 destination defaults" do
    setup do
      dir = watched_root()
      release_folder(dir, "Waiting Release", ["book.m4b"])
      source = insert(:source, path: dir, import_policy: :hardlink)
      root = insert(:root)

      {:ok, _counts} = Inbox.discover()
      {[item], false} = Inbox.list_items(filter: "Waiting Release")
      {:ok, item} = Inbox.probe_item(item)
      {:ok, item} = Inbox.prepare_draft(item)

      %{item: item, source: source, root: root}
    end

    test "a seeded destination is resolved, but not the operator's", %{item: item, root: root} do
      assert item.draft.destination.root_id == root.id
      assert item.draft.destination.policy == :hardlink
      assert Destination.resolved?(item.draft.destination)
      refute item.draft.destination.root_chosen
      refute item.draft.destination.policy_chosen
    end

    test "an untouched destination follows the default when it moves", ctx do
      {:ok, _source} = Library.update_source(ctx.source, %{import_policy: :move})

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.policy == :move
      refute item.draft.destination.policy_chosen
    end

    test "a policy the operator chose is never moved by a default", ctx do
      pick(ctx.item, &Destination.choose_policy(&1, :copy))

      {:ok, _source} = Library.update_source(ctx.source, %{import_policy: :move})

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.policy == :copy
      assert item.draft.destination.policy_chosen
    end

    # The two halves are separate decisions: "where" is not an answer to
    # "how", and one flag would have made picking a root freeze whatever
    # policy the previous root happened to imply.
    test "picking a root leaves an unpicked policy free to follow the default", ctx do
      other = insert(:root)
      pick(ctx.item, &Destination.choose_root(&1, other.id))

      {:ok, _source} = Library.update_source(ctx.source, %{import_policy: :move})

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.root_id == other.id
      assert item.draft.destination.root_chosen
      assert item.draft.destination.policy == :move
    end

    # Blank is how an operator un-decides; recording it as a choice would
    # leave the import unresolvable with no way back.
    test "clearing a picker hands the choice back to the default", ctx do
      other = insert(:root)
      pick(ctx.item, &Destination.choose_root(&1, other.id))
      pick(Inbox.get_item!(ctx.item.id), &Destination.choose_root(&1, nil))

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      refute item.draft.destination.root_chosen
      # two roots now, and no preference between them
      assert is_nil(item.draft.destination.root_id)
    end

    # A root can be deleted between the choice and the next look, and a
    # dangling id would seed a destination that only fails at placement.
    test "a chosen root that has since been deleted is asked about again", ctx do
      doomed = insert(:root)
      pick(ctx.item, &Destination.choose_root(&1, doomed.id))
      {:ok, _root} = Library.delete_root(doomed)

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert is_nil(item.draft.destination.root_id)
      refute Destination.resolved?(item.draft.destination)
    end

    test "re-preparing an unchanged item changes nothing", ctx do
      {:ok, again} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert again.draft.destination == ctx.item.draft.destination
    end

    # What the form's pickers do: transform the stored destination and save.
    defp pick(item, fun) do
      draft = %{item.draft | destination: fun.(item.draft.destination)}
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      item
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
      {:ok, _counts} = discover(root)
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
      {:ok, _counts} = discover(root)

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
      {:ok, _counts} = discover(root)
      release_folder(root, "Found second", ["book.m4b"])
      {:ok, _counts} = discover(root)

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
      {:ok, _counts} = discover(root)

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

    # The stored columns are the source's coordinates, never the disk's:
    # that is what lets a source's mount point move without stranding
    # everything queued under it.
    test "stores every path relative to the source it was found in" do
      source = insert(:source, path: watched_root())
      release = release_folder(source.path, "Leviathan Wakes", ["book.m4b"])

      assert {:ok, %{created: 1}} = Inbox.discover()

      assert {[item], false} = Inbox.list_items()
      assert item.source_id == source.id
      assert item.path == "Leviathan Wakes"
      assert item.files == ["Leviathan Wakes/book.m4b"]
      assert InboxItem.disk_path(item) == release
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
      assert {:ok, %{created: 1}} = discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, children} = Inbox.split_item(item)

      assert Enum.sort(Enum.map(children, &InboxItem.disk_path/1)) ==
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
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item)

      assert {:ok, %{created: 0}} = discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 2
      assert Enum.all?(items, &(length(&1.files) == 1))
    end

    test "a file that appears in a split folder becomes its own item" do
      root = watched_root()
      release = release_folder(root, "Two Novellas", ["one.m4b", "two.m4b"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, _children} = Inbox.split_item(item)

      copy_audio(release, "three.m4b")

      assert {:ok, %{created: 1}} = discover(root)

      {items, false} = Inbox.list_items()
      assert length(items) == 3
      assert Enum.any?(items, &(InboxItem.disk_path(&1) == Path.join(release, "three.m4b")))
    end

    test "refuses an imported item and a single-file item" do
      imported = raw_item(%{path: "two", files: ["a.m4b", "b.m4b"], status: :imported})
      assert {:error, :already_imported} = Inbox.split_item(imported)

      single = raw_item(%{path: "only.m4b", files: ["only.m4b"]})
      assert {:error, :not_multi_file} = Inbox.split_item(single)
    end
  end

  defp raw_item(attrs) do
    attrs = Map.put_new_lazy(attrs, :source_id, fn -> insert(:source).id end)
    %InboxItem{} |> InboxItem.changeset(attrs) |> Repo.insert!()
  end

  # Every item comes from a source, so the walk is only ever exercised
  # through one. Get-or-create because rescanning the same tree is the point
  # of half these tests.
  defp discover(root) do
    source = Repo.get_by(Source, path: root) || insert(:source, path: root)
    Inbox.discover(source)
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
