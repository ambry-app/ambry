defmodule Ambry.InboxTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
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
    # Discovery used to skip these, which made a release the library already
    # holds invisible — and that release is exactly the work when a legacy
    # recording is being upgraded to direct play. The provenance is now a
    # suggestion on the import form, not a filter here.
    test "offers files a legacy media was imported from" do
      root = watched_root()
      release = release_folder(root, "Already Imported", ["book.m4b"])

      insert(:media, book: build(:book), legacy_source_files: [Path.join(release, "book.m4b")])

      assert {:ok, %{created: 1}} = discover(root)
      assert {[item], false} = Inbox.list_items()
      assert item.path == "Already Imported"
    end

    # The scanned folder doubles as a registered root here — that's the one
    # arrangement where a scan can meet the library's own files.
    test "offers files the library already serves as direct-play tracks" do
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

      assert {:ok, %{created: 1}} = discover(root)
      assert {[_item], false} = Inbox.list_items()
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
      source = insert(:source, path: dir)
      root = insert(:root, path: watched_root())
      {:ok, _memory} = Library.remember_placement(source, root, :hardlink)

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
      {:ok, _memory} = Library.remember_placement(ctx.source, ctx.root, :move)

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.policy == :move
      refute item.draft.destination.policy_chosen
    end

    test "a policy the operator chose is never moved by a default", ctx do
      pick(ctx.item, &Destination.choose_policy(&1, :copy))

      {:ok, _memory} = Library.remember_placement(ctx.source, ctx.root, :move)

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.policy == :copy
      assert item.draft.destination.policy_chosen
    end

    # The two halves are separate decisions: "where" is not an answer to
    # "how", and one flag would have made picking a root freeze whatever
    # policy the previous root happened to imply — here, the first root's
    # remembered hardlink following the operator to a root that has its own
    # answer.
    test "picking a root leaves an unpicked policy free to follow the default", ctx do
      other = insert(:root, path: watched_root())
      {:ok, _memory} = Library.remember_placement(ctx.source, other, :move)

      pick(ctx.item, &Destination.choose_root(&1, other.id))

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      assert item.draft.destination.root_id == other.id
      assert item.draft.destination.root_chosen
      assert item.draft.destination.policy == :move
      refute item.draft.destination.policy_chosen
    end

    # Blank is how an operator un-decides; recording it as a choice would
    # leave the import unresolvable with no way back.
    test "clearing a picker hands the choice back to the default", ctx do
      other = insert(:root, path: watched_root())
      pick(ctx.item, &Destination.choose_root(&1, other.id))
      pick(Inbox.get_item!(ctx.item.id), &Destination.choose_root(&1, nil))

      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(ctx.item.id))

      refute item.draft.destination.root_chosen
      # back to the remembered root, not stuck on the one just cleared
      assert item.draft.destination.root_id == ctx.root.id
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

    # The card does not narrate. What import will do is the two pickers'
    # own values, read off the controls; prose appears only when something
    # can't happen. A sentence restating a choice back at the operator is
    # noise on every visit after the first.
    test "an unpicked policy is outstanding, and nothing is narrated" do
      dir = watched_root()
      release_folder(dir, "No Policy Yet", ["book.m4b"])
      source = insert(:source, path: dir)
      # An unmounted root: nothing can be derived from a path that isn't
      # there, and guessing is what the whole refusal exists to prevent.
      root = insert(:root, path: "/data/not-mounted")

      {:ok, _counts} = Inbox.discover()
      {[item], false} = Inbox.list_items(filter: "No Policy Yet")
      {:ok, item} = Inbox.probe_item(item)
      {:ok, item} = Inbox.prepare_draft(item)

      assert is_nil(item.draft.destination.policy)
      assert Enum.any?(Draft.unresolved(item.draft), &(&1.section == :destination))

      refute Map.has_key?(Inbox.destination_preflight(item), :summary)

      # The remembered pairing is what settles it from then on, still
      # without a sentence about it.
      {:ok, _memory} = Library.remember_placement(source, root, :move)
      {:ok, item} = Inbox.prepare_draft(Inbox.get_item!(item.id))

      assert item.draft.destination.policy == :move
      assert Inbox.destination_preflight(item) == %{blocker: nil}
    end
  end

  # Production, 2026-08-20: the operator answered "this replaces audiobook
  # 108", a sibling import's post-commit sweep wrote the whole draft back
  # from a copy of the row it had read seconds earlier, and the answer
  # stopped existing. The import job then refused an item whose form showed
  # nothing wrong, and no job failed anywhere.
  describe "concurrent writes to one item" do
    setup do
      dir = watched_root()
      release_folder(dir, "Contested Item", ["book.m4b"])
      insert(:source, path: dir)
      insert(:root, path: watched_root())

      {:ok, _counts} = Inbox.discover()
      {[item], false} = Inbox.list_items(filter: "Contested Item")
      {:ok, item} = Inbox.probe_item(item)
      {:ok, item} = Inbox.prepare_draft(item)

      %{item: item}
    end

    test "an answer given while a sweep was working is not written back over", ctx do
      # what the sweep read before the operator touched anything
      sweep_holds = ctx.item

      media = insert(:media, book: insert(:book))

      {:ok, _answered} =
        Inbox.update_draft_with(ctx.item, fn draft, _item ->
          Draft.Edit.replace_recording(draft, media.id)
        end)

      {:ok, _swept} =
        Inbox.update_draft_with(sweep_holds, fn draft, _item -> %{draft | stale: true} end)

      draft = Inbox.get_item!(ctx.item.id).draft

      # the sweep's own change landed...
      assert draft.stale
      # ...on top of the answer, rather than instead of it
      assert %{mode: :replace, curated: true} = draft.replacement
      assert draft.replacement.media_id == media.id
    end

    test "a sweep that finds nothing to do leaves no trace", ctx do
      {:ok, item} = Inbox.update_draft_with(ctx.item, fn draft, _item -> draft end)

      # Not merely "the draft is the same": the row must not move at all, or
      # a form somebody has open goes stale every time an unrelated item is
      # imported. `Draft`'s keyless collections make every re-cast look like
      # a change, so this is the assertion that keeps that quirk contained.
      assert item.lock_version == ctx.item.lock_version
      assert {:ok, _saved} = Inbox.update_draft(ctx.item, Inbox.dump_draft(ctx.item.draft))
    end

    # The form's params are the one write that can't be replayed against a
    # newer draft: they were rendered against a particular one.
    test "form params rendered against a draft the row has moved past are refused", ctx do
      {:ok, _moved} =
        Inbox.update_draft_with(ctx.item, fn draft, _item -> %{draft | stale: true} end)

      assert {:error, :stale} = Inbox.update_draft(ctx.item, Inbox.dump_draft(ctx.item.draft))
      assert Inbox.get_item!(ctx.item.id).draft.stale
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

    # The point of the item's own index: a release folder named for a part
    # number says nothing about what the book is, and the draft does.
    test "finds an item by what its draft says, not just by its path" do
      root = watched_root()
      release_folder(root, "01 Angels and Demons.m4b", ["book.m4b"])
      {:ok, _counts} = discover(root)

      {[item], false} = Inbox.list_items()
      {:ok, item} = Inbox.prepare_draft(item)

      assert {[], false} = Inbox.list_items(filter: "Dan Brown")

      draft =
        put_in(
          item.draft,
          [Access.key(:work), Access.key(:authors)],
          [%Draft.Credit{name: "Dan Brown", kind: :author, mode: :create}]
        )

      {:ok, _item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert {[found], false} = Inbox.list_items(filter: "Dan Brown")
      assert found.id == item.id

      # and still by its path
      assert {[^found], false} = Inbox.list_items(filter: "angels")
    end

    test "punctuation in a folder name does not hide it" do
      root = watched_root()
      release_folder(root, "Truly, Devious [2]", ["book.m4b"])
      {:ok, _counts} = discover(root)

      assert {[item], false} = Inbox.list_items(filter: "truly devious")
      assert InboxItem.name(item) == "Truly, Devious [2]"
    end

    # The filter interpolated the phrase straight into an `ILIKE` pattern, so
    # typing a percent sign matched the whole queue. It matches nothing now:
    # a phrase with no lexemes in it is a phrase nothing can satisfy, which
    # is a different answer from an empty box.
    test "a wildcard is punctuation, not a pattern" do
      root = watched_root()
      release_folder(root, "Keeper", ["book.m4b"])
      {:ok, _counts} = discover(root)

      assert {[], false} = Inbox.list_items(filter: "%")
      assert {[], false} = Inbox.list_items(filter: "_eeper")
      assert {[_keeper], false} = Inbox.list_items(filter: "Keeper")
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
        insert(:source, path: watched_root())

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

  # The grouping heuristic's other known failure, and the mirror of a split:
  # a release whose parts sit in subfolders that don't say they are parts
  # ("Gwendy's Button Box 2" is a book, not a disc) arrives as one item per
  # subfolder. Combining is the operator's correction, and like a split it
  # has to survive the hourly rescan or it silently un-happens.
  describe "combine_items/1" do
    test "makes one item of a release the walk shattered into subfolders" do
      root = watched_root()
      book = shattered_release(root)

      assert {:ok, %{created: 3}} = discover(root)
      {items, false} = Inbox.list_items()

      assert {:ok, combined} = Inbox.combine_items(items)

      assert InboxItem.disk_path(combined) == book
      assert {[only], false} = Inbox.list_items()
      assert only.id == combined.id

      # read from scratch: each part's probe, tags and matches described a
      # different audiobook
      assert_enqueued(worker: Ambry.Inbox.RunProbe, args: %{inbox_item_id: combined.id})
      for item <- items, do: refute(Repo.get(InboxItem, item.id))
    end

    # The files are one book's timeline now, so their order is playing order,
    # and it has to be the order a single candidate for that folder would
    # have found them in.
    test "holds every file, in the order a scan of the folder would give" do
      root = watched_root()
      book = shattered_release(root)
      {:ok, _counts} = discover(root)
      {items, false} = Inbox.list_items()

      assert {:ok, combined} = Inbox.combine_items(items)

      assert InboxItem.disk_files(combined) == [
               Path.join(book, "Gwendy's Button Box 1/Track01.mp3"),
               Path.join(book, "Gwendy's Button Box 1/Track02.mp3"),
               Path.join(book, "Gwendy's Button Box 2/Track01.mp3"),
               Path.join(book, "Gwendy's Button Box 2/Track02.mp3"),
               Path.join(book, "Gwendy's Button Box 3/Track01.mp3")
             ]
    end

    # The walk cannot see what the operator saw, so it still offers those
    # three subfolders as three candidates every hour. Ownership is what
    # answers them, and it is only answerable once the whole walk is in:
    # refreshing the item from each candidate in turn left it holding
    # whichever ran last.
    test "a rescan respects the combine instead of shattering the folder again" do
      root = watched_root()
      shattered_release(root)
      {:ok, _counts} = discover(root)
      {items, false} = Inbox.list_items()
      {:ok, combined} = Inbox.combine_items(items)

      assert {:ok, %{created: 0, updated: 0}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert item.files == combined.files
      refute Inbox.get_item!(item.id).draft
    end

    test "a file that appears in a combined folder joins it" do
      root = watched_root()
      book = shattered_release(root)
      {:ok, _counts} = discover(root)
      {items, false} = Inbox.list_items()
      {:ok, combined} = Inbox.combine_items(items)

      copy_audio(Path.join(book, "Gwendy's Button Box 3"), "Track02.mp3")

      assert {:ok, %{created: 0, updated: 1}} = discover(root)

      assert {[item], false} = Inbox.list_items()
      assert length(item.files) == length(combined.files) + 1
    end

    test "refuses an imported item, a lone item, and two sources" do
      source = insert(:source)
      one = raw_item(%{path: "Set/One", files: ["Set/One/a.mp3"], source_id: source.id})

      imported =
        raw_item(%{
          path: "Set/Two",
          files: ["Set/Two/a.mp3"],
          status: :imported,
          source_id: source.id
        })

      assert {:error, :already_imported} = Inbox.combine_items([one, imported])
      assert {:error, :not_multiple} = Inbox.combine_items([one])

      elsewhere = raw_item(%{path: "Set/Three", files: ["Set/Three/a.mp3"]})
      assert {:error, :different_sources} = Inbox.combine_items([one, elsewhere])
    end

    # An item at the top of a source shares only the watched folder itself,
    # and an item there would own every file that ever lands in it.
    test "refuses items that share nothing but the source root" do
      source = insert(:source)
      one = raw_item(%{path: "One.m4b", files: ["One.m4b"], source_id: source.id})
      two = raw_item(%{path: "Two/a.mp3", files: ["Two/a.mp3"], source_id: source.id})

      assert {:error, :no_shared_folder} = Inbox.combine_items([one, two])
    end

    test "refuses when something else already holds the folder" do
      source = insert(:source)
      one = raw_item(%{path: "Set/One", files: ["Set/One/a.mp3"], source_id: source.id})
      two = raw_item(%{path: "Set/Two", files: ["Set/Two/a.mp3"], source_id: source.id})
      _squatter = raw_item(%{path: "Set", files: [], source_id: source.id, status: :ignored})

      assert {:error, :path_taken} = Inbox.combine_items([one, two])
    end
  end

  # A release that ships the same part twice — Oathbringer's second part
  # carries STORMLIGHT0302P06.mp3 and STORMLIGHT0302P06_CD.mp3, the same forty
  # minutes at two bitrates. Splitting doesn't help and ignoring takes the
  # whole item out, so one file goes and the rest stay.
  describe "exclude_file/2" do
    test "takes a file out of the recording without letting go of it" do
      root = watched_root()
      release = release_folder(root, "Oathbringer", ["P05.mp3", "P06.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()

      assert {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")

      # still held — that is what stops the next scan adopting it
      assert length(item.files) == 3
      assert item.excluded_files == ["Oathbringer/P06_CD.mp3"]

      assert InboxItem.disk_files(item) == [
               Path.join(release, "P05.mp3"),
               Path.join(release, "P06.mp3")
             ]

      assert length(InboxItem.owned_disk_files(item)) == 3

      # the recording changed length, so it is read again
      assert_enqueued(worker: Ambry.Inbox.RunProbe, args: %{inbox_item_id: item.id})
    end

    # The whole reason the file stays in `files`. A shorter list would leave
    # it owned by nobody, and discovery hands an unowned file in a
    # partly-owned folder an item of its own — every hour, forever.
    test "a rescan does not offer an excluded file as an item of its own" do
      root = watched_root()
      release_folder(root, "Oathbringer", ["P05.mp3", "P06.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")

      assert {:ok, %{created: 0, updated: 0}} = discover(root)

      assert {[unchanged], false} = Inbox.list_items()
      assert unchanged.id == item.id
      assert unchanged.excluded_files == item.excluded_files
    end

    test "probing measures the recording, not everything held" do
      root = watched_root()
      release_folder(root, "Oathbringer", ["P05.mp3", "P06.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, whole} = Inbox.probe_item(item)

      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")
      {:ok, part} = Inbox.probe_item(item)

      assert part.probe["files"] == 2
      assert whole.probe["files"] == 3

      assert Decimal.lt?(
               Decimal.new(part.probe["duration"]),
               Decimal.new(whole.probe["duration"])
             )
    end

    test "putting it back restores the recording" do
      root = watched_root()
      release_folder(root, "Oathbringer", ["P05.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()

      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")
      assert {:ok, item} = Inbox.include_file(item, "Oathbringer/P06_CD.mp3")

      assert item.excluded_files == []
      assert length(InboxItem.disk_files(item)) == 2
    end

    test "refuses the last file, a file it doesn't hold, and an imported item" do
      root = watched_root()
      release_folder(root, "Oathbringer", ["P05.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()

      assert {:error, :not_held} = Inbox.exclude_file(item, "Oathbringer/nope.mp3")

      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")
      assert {:error, :last_file} = Inbox.exclude_file(item, "Oathbringer/P05.mp3")

      {:ok, imported} = Inbox.update_item(item, %{status: :imported})
      assert {:error, :already_imported} = Inbox.exclude_file(imported, "Oathbringer/P05.mp3")
    end

    # An excluded file is a decision about the recording, so a draft built
    # before it says so.
    test "a curated draft is told the recording changed" do
      root = watched_root()
      release_folder(root, "Oathbringer", ["P05.mp3", "P06.mp3", "P06_CD.mp3"])
      {:ok, _counts} = discover(root)
      {[item], false} = Inbox.list_items()
      {:ok, item} = Inbox.probe_item(item)
      {:ok, item} = Inbox.prepare_draft(item)
      refute item.draft.stale

      {:ok, item} = Inbox.exclude_file(item, "Oathbringer/P06_CD.mp3")

      assert Inbox.get_item!(item.id).draft.stale
    end
  end

  describe "combine_group/1" do
    test "offers the rest of the folder, and nothing at the top of a source" do
      root = watched_root()
      shattered_release(root)
      loose = copy_audio(root, "Gwendy's Final Task.m4b")
      {:ok, _counts} = discover(root)

      {items, false} = Inbox.list_items()
      by_path = Map.new(items, &{InboxItem.disk_path(&1), &1})

      assert %{items: offered, folder: folder} =
               Inbox.combine_group(
                 by_path[Path.join(root, "Gwendy's Button Box/Gwendy's Button Box 1")]
               )

      assert length(offered) == 3
      assert folder == "Gwendy's Button Box"

      # a loose file at the top shares only the watched folder with them
      assert Inbox.combine_group(by_path[loose]) == nil
    end

    test "offers nothing once the folder holds one waiting item" do
      root = watched_root()
      release_folder(Path.join(root, "Set"), "Only", ["a.mp3"])
      {:ok, _counts} = discover(root)

      {[item], false} = Inbox.list_items()
      assert Inbox.combine_group(item) == nil
    end

    test "an imported item is not up for regrouping" do
      root = watched_root()
      shattered_release(root)
      {:ok, _counts} = discover(root)
      {[item | _rest], false} = Inbox.list_items()
      {:ok, item} = Inbox.update_item(item, %{status: :imported})

      assert Inbox.combine_group(item) == nil
    end
  end

  describe "queue_summary/0" do
    test "splits pending into ready, waiting on a decision, and never asked" do
      ready_item(%{path: "ready"})
      drafted_item(%{path: "drafted"})
      raw_item(%{path: "never-asked"})

      assert %{pending: 3, ready: 1, decisions_needed: 1, unprepared: 1} = Inbox.queue_summary()
    end

    test "the three buckets always add up to pending" do
      for n <- 1..4, do: drafted_item(%{path: "d#{n}"})
      for n <- 1..2, do: ready_item(%{path: "r#{n}"})

      summary = Inbox.queue_summary()

      assert summary.ready + summary.decisions_needed + summary.unprepared == summary.pending
    end

    test "settled items are history, not queue" do
      raw_item(%{path: "gone", status: :imported})
      raw_item(%{path: "no-thanks", status: :ignored})

      assert %{pending: 0, ready: 0, decisions_needed: 0, unprepared: 0} = Inbox.queue_summary()
    end

    test "issues cut across the buckets rather than forming one" do
      ready_item(%{path: "ready-but-troubled", issue: "couldn't read a tag"})

      assert %{pending: 1, ready: 1, issues: 1} = Inbox.queue_summary()
    end
  end

  describe "provider_health/0" do
    test "rolls outcomes up per recorded id, keeping kinds apart" do
      raw_item(%{
        path: "one",
        matches: %{
          "work" => %{
            "providers" => [
              %{"id" => "hardcover", "name" => "Hardcover", "status" => "ok", "count" => 3},
              %{
                "id" => "hardcover:details",
                "name" => "Hardcover details",
                "status" => "failed",
                "count" => 0,
                "reason" => "rate limited"
              }
            ]
          }
        }
      })

      raw_item(%{
        path: "two",
        matches: %{
          "recording" => %{
            "providers" => [
              %{"id" => "hardcover", "name" => "Hardcover", "status" => "ok", "count" => 1}
            ]
          }
        }
      })

      health = Map.new(Inbox.provider_health(), &{&1.id, &1})

      assert %{calls: 2, failures: 0} = health["hardcover"]
      assert %{calls: 1, failures: 1, reason: "rate limited"} = health["hardcover:details"]
    end

    test "reads person-level outcomes too" do
      raw_item(%{
        path: "one",
        matches: %{
          "people" => %{
            "author:Andy Weir" => %{
              "providers" => [
                %{"id" => "wikidata", "name" => "Wikipedia", "status" => "ok", "count" => 2}
              ]
            }
          }
        }
      })

      assert [%{id: "wikidata", calls: 1}] = Inbox.provider_health()
    end

    test "describes the open queue, not what has already been imported" do
      outcomes = %{
        "work" => %{
          "providers" => [
            %{"id" => "audible", "name" => "Audible", "status" => "ok", "count" => 1}
          ]
        }
      }

      raw_item(%{path: "done", status: :imported, matches: outcomes})

      assert Inbox.provider_health() == []
    end

    test "an item that was never matched contributes nothing and crashes nothing" do
      raw_item(%{path: "unmatched"})

      assert Inbox.provider_health() == []
    end
  end

  defp raw_item(attrs) do
    attrs = Map.put_new_lazy(attrs, :source_id, fn -> insert(:source).id end)
    %InboxItem{} |> InboxItem.changeset(attrs) |> Repo.insert!()
  end

  # An empty draft is one nobody has resolved, which is exactly the
  # "waiting on a decision" bucket.
  defp drafted_item(attrs) do
    attrs |> raw_item() |> InboxItem.put_draft(%{}) |> Repo.update!()
  end

  # `ready` is set here rather than by resolving a whole draft: the summary
  # reads the column, and building a genuinely resolved draft would be
  # testing `Draft.resolved?/1` a second time in the wrong file.
  defp ready_item(attrs) do
    attrs
    |> drafted_item()
    |> Ecto.Changeset.change(ready: true)
    |> Repo.update!()
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

  # The operator's real case: three subfolders that are one audiobook, named
  # so that nothing but a human could tell them from three books.
  defp shattered_release(root) do
    book = Path.join(root, "Gwendy's Button Box")

    for {part, files} <- [
          {"1", ["Track01.mp3", "Track02.mp3"]},
          {"2", ["Track01.mp3", "Track02.mp3"]},
          {"3", ["Track01.mp3"]}
        ] do
      release_folder(book, "Gwendy's Button Box #{part}", files)
    end

    book
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
