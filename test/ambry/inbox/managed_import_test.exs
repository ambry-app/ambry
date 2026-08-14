defmodule Ambry.Inbox.ManagedImportTest do
  @moduledoc """
  Approving an item that came from a downloads folder, which is the first
  point where Ambry writes to the library rather than just reading it.
  """
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Library
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

      assert [placed] = media.source_files

      assert placed ==
               Path.join([
                 root,
                 "Brandon Sanderson",
                 "The Way of Kings (2010)",
                 "The Way of Kings [#{Media.filename_token(media)}].m4b"
               ])

      assert File.exists?(placed)

      # the whole point: one inode, two names, no extra bytes
      assert {:ok, %{links: 2}} = File.stat(placed)
      assert File.exists?(source)

      assert [%{path: ^placed}] = media.media_tracks
      assert media.source_path == Path.dirname(placed)
    end

    test "gives a multi-file recording a subfolder of its own, with indexed names" do
      %{item: item, root: root, sources: sources} =
        downloads_item(files: ["02.m4b", "01.m4b", "10.m4b"])

      assert {:ok, media} = Inbox.import_item(item)
      media = Media.get_media!(media.id)

      book_folder = Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)"])

      # A subfolder, because the book folder is shared with every other
      # recording of the same work — and indexed names, because play order
      # has to be legible on disk rather than inherited from whatever the
      # release called things. The folder carries the recording's token; the
      # files inside it don't repeat it.
      recording_folder =
        Path.join(book_folder, "The Way of Kings [#{Media.filename_token(media)}]")

      assert media.source_files == [
               Path.join(recording_folder, "The Way of Kings - 001.m4b"),
               Path.join(recording_folder, "The Way of Kings - 002.m4b"),
               Path.join(recording_folder, "The Way of Kings - 003.m4b")
             ]

      assert Enum.all?(media.source_files, &File.exists?/1)
      assert media.source_path == recording_folder

      # 01 before 02 before 10: the order the operator saw, not the order the
      # filenames sort as strings.
      assert media.media_tracks
             |> Enum.sort_by(& &1.index)
             |> Enum.map(& &1.path) == media.source_files

      # Every one hardlinked, and every source still seeding.
      assert Enum.all?(media.source_files, &match?({:ok, %{links: 2}}, File.stat(&1)))
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

      assert [placed] = Media.get_media!(media.id).source_files

      assert placed ==
               Path.join([
                 root,
                 "Brandon Sanderson",
                 "2010 - The Way of Kings",
                 "The Way of Kings [#{Media.filename_token(media)}].m4b"
               ])
    end

    test "moves instead, leaving the downloads folder clean" do
      %{item: item, source: source} = downloads_item(policy: :move)

      assert {:ok, media} = Inbox.import_item(item)

      assert [placed] = Media.get_media!(media.id).source_files
      assert File.exists?(placed)
      # the source is removed only after the records committed
      refute File.exists?(source)
    end

    test "copies when asked to, duplicating deliberately" do
      %{item: item, source: source} = downloads_item(policy: :copy)

      assert {:ok, media} = Inbox.import_item(item)

      assert [placed] = Media.get_media!(media.id).source_files
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

      folder = Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)"])

      assert [placed1] = Media.get_media!(media1.id).source_files
      assert [placed2] = Media.get_media!(media2.id).source_files

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

      assert File.exists?(placed1)
      assert File.exists?(placed2)
    end

    # The deletion worker rm_rfs a managed media's source folder. Parts share
    # theirs, so deleting part 1 that way would take part 2's file with it.
    test "deleting one part leaves its sibling's file alone" do
      %{media1: media1, media2: media2} = two_part_imports()

      [placed1] = Media.get_media!(media1.id).source_files
      [placed2] = Media.get_media!(media2.id).source_files

      assert {:ok, _deleted} = Media.delete_media(Media.get_media!(media1.id))
      # file deletion happens in a background job on the default queue
      assert %{success: _some, failure: 0} = Oban.drain_queue(queue: :default)

      refute File.exists?(placed1)
      assert File.exists?(placed2)
    end

    defp two_part_imports do
      root = new_dir("root")
      insert(:root, path: root, name: "Library")

      downloads = new_dir("downloads")

      for n <- 1..2 do
        release = Path.join(downloads, "The Way of Kings Part #{n}")
        File.mkdir_p!(release)
        File.cp!(tagged_audio(), Path.join(release, "book.m4b"))
      end

      watched =
        insert(:source,
          import_policy: :copy,
          path: downloads,
          name: "Downloads #{Ecto.UUID.generate()}"
        )

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
      insert(:root, path: new_dir("second-root"))
      %{item: item} = downloads_item()

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

      assert [placed] = Media.get_media!(media.id).source_files
      assert String.starts_with?(placed, chosen.path)
    end

    test "a source's preferred root preselects without binding" do
      %{item: item, watched: watched} = downloads_item()

      chosen = insert(:root, path: new_dir("preferred-root"))

      {:ok, _watched} = Library.update_source(watched, %{target_root_id: chosen.id})

      {:ok, item} = Inbox.rebuild_draft(Repo.reload(item))

      assert item.draft.destination.root_id == chosen.id
      assert item.draft.destination.approved
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

      [placed1] = Media.get_media!(media1.id).source_files
      [placed2] = Media.get_media!(media2.id).source_files

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

  describe "other sources" do
    # The successor to leave-in-place: the files stay exactly where they are
    # and the library holds pointers to them, but the pointers are Ambry's
    # own names inside a root, organized by the template like everything
    # else.
    test "a symlink source's files stay where they lie, referenced by links" do
      %{item: item, source: source, root: root} = downloads_item(policy: :symlink)

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert [placed] = media.source_files
      assert String.starts_with?(placed, root)
      assert File.read_link(placed) == {:ok, source}
      assert File.exists?(source)
    end
  end

  defp downloads_item(opts \\ []) do
    policy = Keyword.get(opts, :policy, :hardlink)

    root =
      case Keyword.get(opts, :root, :default) do
        :none -> nil
        :default -> new_dir("root")
        path -> path
      end

    if root do
      insert(:root, path: root, name: "Library")
    end

    downloads = new_dir("downloads")
    release = Path.join(downloads, "The Way of Kings [M4B]")
    File.mkdir_p!(release)

    sources =
      opts
      |> Keyword.get(:files, ["book.m4b"])
      |> Enum.map(fn name ->
        path = Path.join(release, name)
        File.cp!(tagged_audio(), path)
        path
      end)

    source = hd(sources)

    watched =
      insert(:source,
        import_policy: policy,
        path: downloads,
        name: "Downloads #{Ecto.UUID.generate()}"
      )

    {:ok, _counts} = Inbox.discover(watched)
    {[item], false} = Inbox.list_items()
    {:ok, item} = Inbox.probe_item(item)

    # Approval executes a resolved draft, so these tests arrange one the way
    # the import form would leave it — what they're actually about is what
    # happens to the bytes afterwards.
    item = settle(item)

    %{
      item: item,
      root: root,
      source: source,
      sources: sources,
      watched: watched,
      downloads: downloads
    }
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
