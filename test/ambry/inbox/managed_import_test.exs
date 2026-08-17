defmodule Ambry.Inbox.ManagedImportTest do
  @moduledoc """
  Approving an item that came from a downloads folder, which is the first
  point where Ambry writes to the library rather than just reading it.
  """
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Library
  alias Ambry.Library.ImportPreference
  alias Ambry.Media
  alias Ambry.Settings

  # A genuinely different filesystem, found at compile time, so the
  # cross-filesystem refusal is exercised against the kernel rather than a
  # mock. `/dev/shm` is tmpfs and therefore never the same device as the
  # project checkout.
  @other_filesystem Enum.find(["/dev/shm", "/tmp"], fn candidate ->
                      with true <- File.dir?(candidate),
                           {:ok, %{major_device: theirs}} <- File.stat(candidate),
                           {:ok, %{major_device: ours}} <- File.stat(File.cwd!()) do
                        theirs != ours
                      else
                        _unusable -> false
                      end
                    end)

  describe "importing from a bring-in source" do
    test "hardlinks into the library under the naming template" do
      %{item: item, root: root, source: source} = downloads_item()

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)

      # stored relative to the root the record itself names
      assert media.library_root_id
      assert [placed] = track_paths(media)

      assert placed ==
               Path.join([
                 "Brandon Sanderson",
                 "The Way of Kings (2010)",
                 "The Way of Kings [#{Media.filename_token(media)}].m4b"
               ])

      assert [placed_on_disk] = track_disk_paths(media)
      assert placed_on_disk == Path.join(root, placed)
      assert File.exists?(placed_on_disk)

      # the whole point: one inode, two names, no extra bytes
      assert {:ok, %{links: 2}} = File.stat(placed_on_disk)
      assert File.exists?(source)

      assert [%{path: ^placed, library_root_id: root_id}] = media.media_tracks
      assert root_id == media.library_root_id

      # Nothing transcoded this, so it carries no transcode bookkeeping.
      assert media.source_path == nil
      assert media.source_files == []
    end

    test "gives a multi-file recording a subfolder of its own, with indexed names" do
      %{item: item, root: root, sources: sources} =
        downloads_item(files: ["02.m4b", "01.m4b", "10.m4b"])

      assert {:ok, media} = Inbox.import_item(item)
      media = Media.get_media!(media.id)

      book_folder = Path.join("Brandon Sanderson", "The Way of Kings (2010)")

      # A subfolder, because the book folder is shared with every other
      # recording of the same work — and indexed names, because play order
      # has to be legible on disk rather than inherited from whatever the
      # release called things. The folder carries the recording's token; the
      # files inside it don't repeat it.
      recording_folder =
        Path.join(book_folder, "The Way of Kings [#{Media.filename_token(media)}]")

      # 01 before 02 before 10: the order the operator saw, not the order the
      # filenames sort as strings.
      assert track_paths(media) == [
               Path.join(recording_folder, "The Way of Kings - 001.m4b"),
               Path.join(recording_folder, "The Way of Kings - 002.m4b"),
               Path.join(recording_folder, "The Way of Kings - 003.m4b")
             ]

      placed_on_disk = track_disk_paths(media)
      assert placed_on_disk == Enum.map(track_paths(media), &Path.join(root, &1))
      assert Enum.all?(placed_on_disk, &File.exists?/1)

      # Every one hardlinked, and every source still seeding.
      assert Enum.all?(placed_on_disk, &match?({:ok, %{links: 2}}, File.stat(&1)))
      assert Enum.all?(sources, &File.exists?/1)
    end

    test "lays a multi-file recording's tracks end to end" do
      %{item: item} = downloads_item(files: ["01.m4b", "02.m4b"])

      assert {:ok, media} = Inbox.import_item(item)
      media = Media.get_media!(media.id)

      assert [first, second] = Enum.sort_by(media.media_tracks, & &1.index)
      assert Decimal.equal?(first.start_offset, 0)
      assert Decimal.equal?(second.start_offset, first.duration)

      assert Decimal.equal?(media.duration, Decimal.add(first.duration, second.duration))
    end

    # A destination can no longer be occupied on purpose — the token is only
    # knowable once the record exists, which is exactly the guarantee — so the
    # failure is provoked by a root that can't be written into at all.
    # `Ambry.Library.PlacementTest` covers the file-by-file rollback; what
    # matters here is that the records go back with the bytes.
    test "a placement that fails leaves no records and no files" do
      # Inside a folder of its own, never loose in `source_media/` — the file
      # audit lists that directory and expects only folders, so a stray file
      # there fails unrelated tests depending on run order.
      unusable = Path.join(new_dir("blocked"), "a-file-where-a-root-should-be")
      File.write!(unusable, "not a directory")

      %{item: item, sources: sources} =
        downloads_item(root: unusable, files: ["01.m4b", "02.m4b", "03.m4b"])

      assert {:error, _reason} = Inbox.import_item(item)

      assert Repo.aggregate(Media.Media, :count) == 0
      assert Repo.aggregate(Ambry.Books.Book, :count) == 0
      assert Enum.all?(sources, &File.exists?/1)
      assert Inbox.get_item!(item.id).status == :pending
    end

    test "renders the folder from the operator's template" do
      {:ok, _setting} = Settings.set_library_naming_template("{author}/{year} - {title}")
      %{item: item, root: root} = downloads_item()

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert [placed] = track_paths(media)

      assert placed ==
               Path.join([
                 "Brandon Sanderson",
                 "2010 - The Way of Kings",
                 "The Way of Kings [#{Media.filename_token(media)}].m4b"
               ])

      assert track_disk_paths(media) == [Path.join(root, placed)]
    end

    test "moves instead, leaving the downloads folder clean" do
      %{item: item, source: source} = downloads_item(policy: :move)

      assert {:ok, media} = Inbox.import_item(item)

      assert [placed] = track_disk_paths(Media.get_media!(media.id))
      assert File.exists?(placed)
      # the source is removed only after the records committed
      refute File.exists?(source)
    end

    test "copies when asked to, duplicating deliberately" do
      %{item: item, source: source} = downloads_item(policy: :copy)

      assert {:ok, media} = Inbox.import_item(item)

      assert [placed] = track_disk_paths(Media.get_media!(media.id))
      assert File.exists?(source)
      assert {:ok, %{links: 1}} = File.stat(placed)
    end

    test "marks the item approved and links it to what it became" do
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.import_item(item)

      {[item], false} = Inbox.list_items()
      assert item.status == :imported
      assert item.media_id == media.id
    end
  end

  describe "part-of-a-set placement" do
    # Two parts of one set are two ordinary separate imports that land in the
    # same book folder — the part suffix is what keeps the second placement
    # from colliding with the first.
    test "two part imports share the folder with distinct filenames" do
      %{media1: media1, media2: media2, root: root} = two_part_imports()

      folder = Path.join("Brandon Sanderson", "The Way of Kings (2010)")

      media1 = Media.get_media!(media1.id)
      media2 = Media.get_media!(media2.id)

      assert [placed1] = track_paths(media1)
      assert [placed2] = track_paths(media2)

      assert placed1 ==
               Path.join(
                 folder,
                 "The Way of Kings - Part 1 of 2 [#{Media.filename_token(media1)}].m4b"
               )

      assert placed2 ==
               Path.join(
                 folder,
                 "The Way of Kings - Part 2 of 2 [#{Media.filename_token(media2)}].m4b"
               )

      assert [disk1] = track_disk_paths(media1)
      assert [disk2] = track_disk_paths(media2)
      assert disk1 == Path.join(root, placed1)
      assert disk2 == Path.join(root, placed2)
      assert File.exists?(disk1)
      assert File.exists?(disk2)
    end

    # The deletion worker rm_rfs a managed media's source folder. Parts share
    # theirs, so deleting part 1 that way would take part 2's file with it.
    test "deleting one part leaves its sibling's file alone" do
      %{media1: media1, media2: media2} = two_part_imports()

      [placed1] = track_disk_paths(Media.get_media!(media1.id))
      [placed2] = track_disk_paths(Media.get_media!(media2.id))

      assert {:ok, _deleted} = Media.delete_media(Media.get_media!(media1.id))
      # file deletion happens in a background job on the default queue
      assert %{success: _some, failure: 0} = Oban.drain_queue(queue: :default)

      refute File.exists?(placed1)
      assert File.exists?(placed2)
    end

    defp two_part_imports do
      root = new_dir("root")
      root_record = insert(:root, path: root, name: "Library")

      downloads = new_dir("downloads")

      for n <- 1..2 do
        release = Path.join(downloads, "The Way of Kings Part #{n}")
        File.mkdir_p!(release)
        File.cp!(tagged_audio(), Path.join(release, "book.m4b"))
      end

      watched = insert(:source, path: downloads, name: "Downloads #{Ecto.UUID.generate()}")
      {:ok, _memory} = Library.remember_placement(watched, root_record, :copy)

      {:ok, _counts} = Inbox.discover(watched)
      {items, false} = Inbox.list_items()
      [first, second] = Enum.sort_by(items, & &1.path)

      {:ok, first} = Inbox.probe_item(first)
      first = first |> settle() |> with_parts(1, 2)
      {:ok, media1} = Inbox.import_item(first)

      # the second part is the same book — a strong local hit links it the
      # way matching would once the library holds part 1
      {:ok, second} = Inbox.probe_item(second)
      book_id = Media.get_media!(media1.id).book_id

      {:ok, second} =
        Inbox.update_item(second, %{
          matches: %{
            "work" => %{
              "candidates" => [],
              "local" => [%{"id" => book_id, "score" => 1.0}],
              "confidence" => 1.0
            },
            "recording" => %{"candidates" => []},
            "people" => %{}
          }
        })

      # part 2 joins the set part 1 created — a second :create with the same
      # name would (correctly) trip the per-book unique index
      group_id = Media.get_media!(media1.id).recording_group_id
      second = second |> settle() |> with_parts(2, 2, group_id)
      {:ok, media2} = Inbox.import_item(second)

      %{media1: media1, media2: media2, root: root}
    end

    defp with_parts(item, number, total, group_id \\ nil) do
      link = %Ambry.Inbox.Draft.GroupLink{
        mode: if(group_id, do: :link, else: :create),
        recording_group_id: group_id,
        name: "Part Set",
        source: "manual",
        part_number: number,
        parts_total: total,
        approved: true,
        curated: true
      }

      draft = %{item.draft | recording: %{item.draft.recording | recording_group: link}}

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      item
    end
  end

  describe "refusals" do
    # Silently copying instead is the storage doubling this entire phase
    # exists to eliminate, and the operator would never know it happened.
    #
    # Defined only when a real second filesystem exists, so that on a machine
    # without one the test is visibly absent rather than passing vacuously.
    if @other_filesystem do
      test "refuses to hardlink across filesystems rather than copying" do
        root = Path.join(@other_filesystem, "ambry-managed-#{Ecto.UUID.generate()}")
        File.mkdir_p!(root)
        on_exit(fn -> File.rm_rf(root) end)

        %{item: item, source: source} = downloads_item(root: root)

        assert {:error, {:cross_filesystem, ^source, _destination}} = Inbox.import_item(item)

        # library untouched, item still queued
        assert {[item], false} = Inbox.list_items()
        assert item.status == :pending
        assert {[], false} = Media.list_media()
      end
    end

    # Which root an import goes to is a decision now, not a property of the
    # watched folder — so "no root" and "several roots, none chosen" surface
    # as outstanding decisions rather than as failures at the last moment.
    test "refuses when there is no library root to import into" do
      %{item: item} = downloads_item(root: :none)

      assert {:error, {:unresolved, outstanding}} = Inbox.import_item(item)
      assert Enum.any?(outstanding, &(&1.section == :destination))

      {[item], false} = Inbox.list_items()
      assert item.status == :pending
    end

    # With several roots the choice is about which NAS, and therefore about
    # whether hardlinking is possible at all. Guessing is not acceptable.
    test "refuses when several roots exist and none was chosen" do
      # No memory to inherit and no preference to fall back on, so the root
      # is a genuine question — asked once, and answered from then on.
      %{item: item} = downloads_item(policy: :unremembered)
      insert(:root, path: new_dir("second-root"))
      {:ok, item} = Inbox.prepare_draft(Repo.reload(item))

      assert {:error, {:unresolved, outstanding}} = Inbox.import_item(item)
      assert Enum.any?(outstanding, &(&1.section == :destination))
    end

    # Any input may feed any output: the operator picks per import, and a
    # source's configured root only *preselects* one.
    test "uses the root the draft settled on when there are several" do
      chosen =
        insert(:root, path: new_dir("chosen-root"))

      %{item: item} = downloads_item()

      {:ok, item} =
        Inbox.update_draft(item, %{
          "destination" => %{
            "root_id" => chosen.id,
            "policy" => "hardlink",
            "approved" => true
          }
        })

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert media.library_root_id == chosen.id

      assert [placed] = track_disk_paths(media)
      assert String.starts_with?(placed, chosen.path)
    end

    # Which of the four doors an import uses is a fact about the *pairing*,
    # so it is learned rather than configured: the next import from a source
    # proposes what the last one into that root actually did.
    test "the next import proposes what the last one from this source did" do
      %{item: item, watched: watched, root: root} = downloads_item(policy: :hardlink)

      item = pick(item, &Destination.choose_policy(&1, :move))
      assert {:ok, _media} = Inbox.import_item(item)

      assert %ImportPreference{} = memory = Library.recall_placement(watched)
      assert Library.get_root!(memory.library_root_id).path == root
      assert memory.policy == :move

      # a fresh candidate from the same source starts where the last one
      # ended up, not at the source's standing default
      next = second_release(watched)
      {:ok, next} = Inbox.prepare_draft(next)

      assert next.draft.destination.policy == :move
      refute next.draft.destination.policy_chosen
    end

    # The reason the memory is written after the import rather than when the
    # operator picks: the queue's Ready badge reads a stored column, so an
    # item nobody has opened since would go on proposing the old default and
    # look settled while proposing it.
    test "items already queued follow the memory when it moves" do
      %{item: item, watched: watched} = downloads_item(policy: :hardlink)

      queued = second_release(watched)
      {:ok, queued} = Inbox.prepare_draft(queued)
      assert queued.draft.destination.policy == :hardlink

      item = pick(item, &Destination.choose_policy(&1, :copy))
      assert {:ok, _media} = Inbox.import_item(item)

      # not reopened, not prepared — read straight back off the row
      assert Repo.reload(queued).draft.destination.policy == :copy
    end

    test "a policy the operator picked for one release is not moved by the memory" do
      %{item: item, watched: watched} = downloads_item(policy: :hardlink)

      queued = second_release(watched)
      {:ok, queued} = Inbox.prepare_draft(queued)
      queued = pick(queued, &Destination.choose_policy(&1, :symlink))

      item = pick(item, &Destination.choose_policy(&1, :copy))
      assert {:ok, _media} = Inbox.import_item(item)

      assert Repo.reload(queued).draft.destination.policy == :symlink
    end

    # Two recordings of one book used to render to one path and refuse; each
    # now carries its own token, so the same import twice lands twice.
    test "a second recording of the same book no longer collides with the first" do
      %{item: first, watched: watched, downloads: downloads, root: root} = downloads_item()

      assert {:ok, media1} = Inbox.import_item(first)

      # A second reading of the same work, in its own release folder.
      second_release = Path.join(downloads, "The Way of Kings [Re-read]")
      File.mkdir_p!(second_release)
      File.cp!(tagged_audio(), Path.join(second_release, "book.m4b"))
      {:ok, _counts} = Inbox.discover(watched)
      {[second], false} = Inbox.list_items(filter: "Re-read")
      {:ok, second} = Inbox.probe_item(second)

      assert {:ok, media2} = Inbox.import_item(settle(second))

      [placed1] = track_disk_paths(Media.get_media!(media1.id))
      [placed2] = track_disk_paths(Media.get_media!(media2.id))

      # Same book folder, different files, both on disk.
      assert Path.dirname(placed1) == Path.dirname(placed2)

      assert Path.dirname(placed1) ==
               Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)"])

      refute placed1 == placed2
      assert File.exists?(placed1)
      assert File.exists?(placed2)
    end
  end

  describe "publishing on approval" do
    # An approved recording is finished. Leaving it pending forever was the
    # gap that made the inbox produce records nothing could ever see.
    test "publishes when the switch is on" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.import_item(item)
      assert Media.get_media!(media.id).status == :ready
    end

    # The whole point of the switch: the server must never hand a client a
    # direct-play recording before the fleet can play one.
    test "waits in pending when the switch is off" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.import_item(item)
      assert Media.get_media!(media.id).status == :pending
    end

    test "turning the switch on later releases what was waiting" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      %{item: item} = downloads_item()
      {:ok, media} = Inbox.import_item(item)

      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      assert {:ok, %{published: 1}} = Media.publish_pending_direct_play()

      assert Media.get_media!(media.id).status == :ready
    end
  end

  describe "replacing an audiobook's files" do
    # The whole back-catalog reclaim, one decision at a time: a legacy
    # recording was transcoded from a downloads folder, the folder is still
    # there, and discovery no longer hides it. What the operator gets is a
    # queued item that already knows which audiobook it belongs to.
    test "the path evidence proposes it, unapproved" do
      %{item: item, source: source} = downloads_item()
      media = legacy_media(from: [source])

      {:ok, item} = Inbox.prepare_draft(item)

      assert %{mode: :replace, media_id: media_id, approved: false} = item.draft.replacement
      assert media_id == media.id

      assert %{section: :replacement} =
               Enum.find(Draft.unresolved(item.draft), &(&1.section == :replacement))
    end

    # Evidence is not an answer. A release the library was built from turning
    # up again says nothing about whether these files should take its place.
    test "an unanswered proposal blocks the import" do
      %{item: item, source: source} = downloads_item()
      _media = legacy_media(from: [source])
      {:ok, item} = Inbox.prepare_draft(item)

      assert {:error, {:unresolved, _outstanding}} = Inbox.import_item(item)
    end

    test "answering it settles everything the audiobook already knows" do
      %{item: item} = downloads_item(settle: false)
      media = legacy_media()

      item = replace_with(item, media)

      # No book, no credits, no chapters: the audiobook has all of them, and
      # none of them are in question.
      assert Draft.unresolved(item.draft) == []
    end

    test "the recording keeps its own records and gains the files" do
      %{item: item, root: root, source: source} = downloads_item()
      media = legacy_media(from: [source], title: "The Way of Kings")
      before_count = Repo.aggregate(Media.Media, :count)

      item = replace_with(item, media)

      assert {:ok, replaced} = Inbox.import_item(item)
      assert replaced.id == media.id
      assert Repo.aggregate(Media.Media, :count) == before_count

      replaced = Media.get_media!(media.id)

      # the same audiobook: its book, its title, its description
      assert replaced.book_id == media.book_id
      assert replaced.title == "The Way of Kings"
      assert replaced.description == media.description

      # played from tracks in the library now, not from packaged artifacts
      assert [%{path: placed}] = replaced.media_tracks
      assert replaced.library_root_id
      assert File.exists?(Path.join(root, placed))

      refute replaced.mp4_path
      refute replaced.hls_path
      refute replaced.mpd_path

      # The transcode is gone, and so is every record of what fed it: the
      # two source columns, and the pre-refactor provenance the CHECK
      # `media_legacy_source_files_quarantined` forbids a placed recording
      # from keeping.
      assert replaced.source_path == nil
      assert replaced.source_files == []
      refute replaced.legacy_source_files

      assert %{status: :imported, media_id: media_id} = Inbox.get_item!(item.id)
      assert media_id == media.id
    end

    test "the artifacts it was streamed from are deleted" do
      %{item: item, source: source} = downloads_item()
      media = legacy_media(from: [source])
      artifact = Ambry.Paths.web_to_disk(media.mp4_path)

      item = replace_with(item, media)
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      refute File.exists?(artifact)
    end

    # Same book, same recording, so the same token and the same rendered
    # filename. Placement never clobbers, and its own name is the one thing
    # it may take.
    test "replacing files the recording already occupies" do
      %{item: first, source: old_source} = downloads_item()
      {:ok, media} = Inbox.import_item(first)
      [placed] = track_disk_paths(Media.get_media!(media.id))
      assert File.stat!(placed).inode == File.stat!(old_source).inode

      %{item: second, source: new_source} =
        downloads_item(root: :reuse, name: "The Way of Kings [FLAC rip]")

      second = replace_with(second, media)

      assert {:ok, _replaced} = Inbox.import_item(second)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      # the same name, the other file behind it
      replaced = Media.get_media!(media.id)
      assert [^placed] = track_disk_paths(replaced)
      assert File.stat!(placed).inode == File.stat!(new_source).inode
      refute File.exists?(placed <> ".ambry-replaced")
    end

    # Chapters are curated data and these files are a new rip of a recording
    # somebody has already been through — the rule `Ambry.Media.Scanner` has
    # always followed for a rescan.
    test "chapters the recording already has survive" do
      %{item: item, source: source} = downloads_item()

      media =
        legacy_media(
          from: [source],
          chapters: [%{time: Decimal.new(0), title: "The operator's own"}],
          chapter_marker_source: :manual
        )

      item = replace_with(item, media)
      assert {:ok, _replaced} = Inbox.import_item(item)

      replaced = Media.get_media!(media.id)
      assert [%{title: "The operator's own"}] = replaced.chapters
      assert replaced.chapter_marker_source == :manual
    end

    # A legacy recording is published on the strength of the artifacts a
    # replacement retires, so with the switch off it goes back to pending and
    # is released with the rest when the switch is turned on.
    test "a published legacy recording waits for the switch" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      %{item: item, source: source} = downloads_item()
      media = legacy_media(from: [source], status: :ready)

      item = replace_with(item, media)
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert Media.get_media!(media.id).status == :pending

      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      assert {:ok, %{published: 1}} = Media.publish_pending_direct_play()
      assert Media.get_media!(media.id).status == :ready
    end

    test "a published recording stays published when the switch is on" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      %{item: item, source: source} = downloads_item()
      media = legacy_media(from: [source], status: :ready)

      item = replace_with(item, media)
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert Media.get_media!(media.id).status == :ready
    end

    # A recording transcoded before the paths refactor: artifacts under the
    # uploads tree, no tracks, and the absolute downloads paths it was made
    # from quarantined in `legacy_source_files`.
    defp legacy_media(opts \\ []) do
      id = Ecto.UUID.generate()
      workspace = Ambry.Paths.source_media_disk_path(id)
      File.mkdir_p!(workspace)
      File.write!(Path.join(workspace, "book.mp4"), "transcoded")

      insert(
        :media,
        Keyword.merge(
          [
            book: build(:book),
            status: :pending,
            source_path: Ambry.Paths.disk_to_web(workspace),
            legacy_source_files: opts[:from],
            mp4_path: Ambry.Paths.disk_to_web(Path.join(workspace, "book.mp4"))
          ],
          Keyword.delete(opts, :from)
        )
      )
    end

    # What the form's replace control does: settle the decision and save it.
    defp replace_with(item, media) do
      {:ok, item} = Inbox.prepare_draft(item)

      {:ok, item} =
        Inbox.update_draft(
          item,
          item.draft |> Draft.Edit.replace_recording(media.id) |> Inbox.dump_draft()
        )

      item
    end
  end

  # A replacement's destination names are rendered from the recording, not
  # from the files, so the shape of the *count* decides everything: one file
  # lands in the book folder as `Title [token].ext`, several land in a
  # `Title [token]/` subfolder as `Title - 001.ext`. Crossing between those
  # two shapes, and changing how many files there are within the second, is
  # where the names an import takes and the names it has to give up stop
  # lining up — so each transition gets a test that looks at the disk.
  describe "replacing files, when the count changes" do
    test "several files replacing one" do
      %{media: media, placed: [only]} = placed_recording(["book.m4b"])
      book_folder = Path.dirname(only)

      %{item: item, sources: sources} = replacement_item(media, ["01.m4b", "02.m4b", "03.m4b"])
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)
      placed = track_disk_paths(replaced)

      # a recording of its own now: a subfolder inside the book folder it
      # used to sit in directly
      assert length(placed) == 3
      assert [folder] = placed |> Enum.map(&Path.dirname/1) |> Enum.uniq()
      assert Path.dirname(folder) == book_folder
      assert inodes(placed) == inodes(sources)

      # the one file it was is gone, and the book folder holds nothing but
      # the new subfolder — no leftovers, nothing set aside
      refute File.exists?(only)
      assert File.ls!(book_folder) == [Path.basename(folder)]
      assert length(replaced.media_tracks) == 3
    end

    test "one file replacing several" do
      %{media: media, placed: old} = placed_recording(["01.m4b", "02.m4b", "03.m4b"])
      folder = Path.dirname(hd(old))
      book_folder = Path.dirname(folder)

      %{item: item, sources: sources} = replacement_item(media, ["book.m4b"])
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)

      # back in the book folder directly, and the subfolder it emptied is
      # pruned rather than left standing
      assert [placed] = track_disk_paths(replaced)
      assert Path.dirname(placed) == book_folder
      assert inodes([placed]) == inodes(sources)

      refute File.exists?(folder)
      assert File.ls!(book_folder) == [Path.basename(placed)]
      assert length(replaced.media_tracks) == 1
    end

    # The case the names really do collide in: 001 and 002 are taken by the
    # recording being replaced, and 003 and 004 have to go.
    test "fewer files replacing more" do
      %{media: media, placed: old} = placed_recording(["01.m4b", "02.m4b", "03.m4b", "04.m4b"])
      folder = Path.dirname(hd(old))

      %{item: item, sources: sources} = replacement_item(media, ["01.m4b", "02.m4b"])
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)
      placed = track_disk_paths(replaced)

      # the same two names, the other two files behind them
      assert placed == Enum.take(old, 2)
      assert inodes(placed) == inodes(sources)

      # and the names it no longer needs are gone, with nothing set aside
      refute File.exists?(Enum.at(old, 2))
      refute File.exists?(Enum.at(old, 3))
      assert length(File.ls!(folder)) == 2
      assert length(replaced.media_tracks) == 2

      # the timeline is the new files', not a leftover of the old ones
      assert Decimal.equal?(
               replaced.duration,
               Enum.reduce(replaced.media_tracks, Decimal.new(0), &Decimal.add(&2, &1.duration))
             )
    end

    test "more files replacing fewer" do
      %{media: media, placed: old} = placed_recording(["01.m4b", "02.m4b"])
      folder = Path.dirname(hd(old))

      %{item: item, sources: sources} =
        replacement_item(media, ["01.m4b", "02.m4b", "03.m4b", "04.m4b"])

      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)
      placed = track_disk_paths(replaced)

      assert length(placed) == 4
      assert Enum.take(placed, 2) == old
      assert inodes(placed) == inodes(sources)
      assert length(File.ls!(folder)) == 4
      assert length(replaced.media_tracks) == 4
    end

    # Every name collides, so every one is set aside and given back.
    test "the same number of files, name for name" do
      %{media: media, placed: old} = placed_recording(["01.m4b", "02.m4b", "03.m4b"])
      folder = Path.dirname(hd(old))
      before = inodes(old)

      %{item: item, sources: sources} = replacement_item(media, ["01.m4b", "02.m4b", "03.m4b"])
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)
      placed = track_disk_paths(replaced)

      assert placed == old
      assert inodes(placed) == inodes(sources)
      refute inodes(placed) == before
      assert length(File.ls!(folder)) == 3
      assert length(replaced.media_tracks) == 3
    end

    # A rip in another format takes none of the old names, so every one of
    # them is retired rather than reused — and the folder is left holding
    # exactly the new files.
    test "a different format replacing the same number of files" do
      %{media: media, placed: old} = placed_recording(["01.m4b", "02.m4b"])
      folder = Path.dirname(hd(old))

      %{item: item, sources: sources} = replacement_item(media, ["01.mp3", "02.mp3"])
      assert {:ok, _replaced} = Inbox.import_item(item)
      assert %{failure: 0} = Oban.drain_queue(queue: :default)

      replaced = Media.get_media!(media.id)
      placed = track_disk_paths(replaced)

      assert length(placed) == 2
      assert Enum.all?(placed, &(Path.extname(&1) == ".mp3"))
      assert inodes(placed) == inodes(sources)
      assert Enum.all?(old, &(not File.exists?(&1)))
      assert Enum.sort(File.ls!(folder)) == placed |> Enum.map(&Path.basename/1) |> Enum.sort()
    end

    # An ordinary import, so the recording being replaced is a real placed
    # one rather than a fixture — the names it occupies are the names the
    # template renders, which is the whole point of these cases.
    defp placed_recording(files) do
      %{item: item} = downloads_item(files: files, name: "Original #{Ecto.UUID.generate()}")
      {:ok, media} = Inbox.import_item(item)
      media = Media.get_media!(media.id)

      %{media: media, placed: track_disk_paths(media)}
    end

    # Another release of the same book in its own watched folder, settled as a
    # replacement for that recording. The root is the one already registered.
    #
    # Nothing else about it is settled, on purpose: the recording it replaces
    # has the book, the credits and the metadata, so a replacement is
    # importable without any of that being answered — and an untagged rip,
    # which is exactly what the format case needs, could not answer it anyway.
    defp replacement_item(media, files) do
      %{item: item, sources: sources} =
        downloads_item(
          root: :reuse,
          files: files,
          settle: false,
          name: "Replacement #{Ecto.UUID.generate()}"
        )

      %{item: replace_with(item, media), sources: sources}
    end

    # What is actually behind each name. Every policy here is `:hardlink`, so
    # a placed file shares its inode with the source it was placed from —
    # which is how a test can tell "the new file took this name" from "the
    # old one is still there under it".
    defp inodes(paths), do: Enum.map(paths, &File.stat!(&1).inode)
  end

  describe "other sources" do
    # The successor to leave-in-place: the files stay exactly where they are
    # and the library holds pointers to them, but the pointers are Ambry's
    # own names inside a root, organized by the template like everything
    # else.
    test "a symlink source's files stay where they lie, referenced by links" do
      %{item: item, source: source, root: root} = downloads_item(policy: :symlink)

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert [placed] = track_disk_paths(media)
      assert String.starts_with?(placed, root)
      assert File.read_link(placed) == {:ok, source}
      assert File.exists?(source)
    end
  end

  defp downloads_item(opts \\ []) do
    policy = Keyword.get(opts, :policy, :hardlink)
    name = Keyword.get(opts, :name, "The Way of Kings [M4B]")

    # `:reuse` is a second downloads folder feeding the root that is already
    # registered. A second root record for one path would make every
    # destination ambiguous, which is a different test.
    root_record =
      case Keyword.get(opts, :root, :default) do
        :none -> nil
        :reuse -> hd(Library.list_roots())
        :default -> insert(:root, path: new_dir("root"), name: "Library")
        path -> insert(:root, path: path, name: "Library")
      end

    root = root_record && root_record.path

    downloads = new_dir("downloads")
    release = Path.join(downloads, name)
    File.mkdir_p!(release)

    sources =
      opts
      |> Keyword.get(:files, ["book.m4b"])
      |> Enum.map(fn name ->
        path = Path.join(release, name)
        File.cp!(fixture_for(name), path)
        path
      end)

    source = hd(sources)

    watched = insert(:source, path: downloads, name: "Downloads #{Ecto.UUID.generate()}")

    # The policy is a memory of the pairing now, not a field on either end,
    # so a test that wants a particular one seeds it the way an earlier
    # import would have. `:unremembered` leaves the pairing blank, which is
    # what a source that has never imported looks like.
    if root_record && policy != :unremembered do
      {:ok, _memory} = Library.remember_placement(watched, root_record, policy)
    end

    {:ok, _counts} = Inbox.discover(watched)
    {[item], false} = Inbox.list_items(filter: name)
    {:ok, item} = Inbox.probe_item(item)

    # Approval executes a resolved draft, so these tests arrange one the way
    # the import form would leave it — what they're actually about is what
    # happens to the bytes afterwards. A replacement settles the same
    # decisions by collapsing them, so those tests ask for the raw item.
    item = if Keyword.get(opts, :settle, true), do: settle(item), else: item

    %{
      item: item,
      root: root,
      source: source,
      sources: sources,
      watched: watched,
      downloads: downloads
    }
  end

  # Another candidate under the same watched folder, probed and queued.
  defp second_release(watched) do
    release = Path.join(watched.path, "Words of Radiance [M4B]")
    File.mkdir_p!(release)
    File.cp!(tagged_audio(), Path.join(release, "book.m4b"))

    {:ok, _counts} = Inbox.discover(watched)
    {[item], false} = Inbox.list_items(filter: "Words of Radiance")
    {:ok, item} = Inbox.probe_item(item)

    item
  end

  # What the form's destination pickers do: transform the stored destination
  # and save it back.
  defp pick(item, fun) do
    draft = %{item.draft | destination: fun.(item.draft.destination)}
    {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
    item
  end

  # A name's extension has to match its bytes. The destination keeps the
  # extension the source had, so a `.mp3` holding mp4 data would be a lie the
  # probe reads straight through — and it is the extension that decides
  # whether a replacement takes the names the old files hold.
  defp fixture_for(name) do
    case Path.extname(name) do
      ".mp3" -> valid_audio(:mp3)
      _m4b -> tagged_audio()
    end
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end

  # Where an import put the files, in play order. `media_tracks` is the only
  # place it says so: `source_path` and `source_files` are what a transcode
  # consumed, and an import is not transcoded.
  defp track_paths(%{media_tracks: tracks}),
    do: tracks |> Enum.sort_by(& &1.index) |> Enum.map(& &1.path)

  defp track_disk_paths(%{media_tracks: tracks}),
    do: tracks |> Enum.sort_by(& &1.index) |> Enum.map(&Media.MediaTrack.disk_path!/1)
end
