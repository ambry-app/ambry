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
      assert media.custody == :managed

      assert [placed] = media.source_files

      assert placed ==
               Path.join([
                 root,
                 "Brandon Sanderson",
                 "The Way of Kings (2010)",
                 "The Way of Kings.m4b"
               ])

      assert File.exists?(placed)

      # the whole point: one inode, two names, no extra bytes
      assert {:ok, %{links: 2}} = File.stat(placed)
      assert File.exists?(source)

      assert [%{path: ^placed}] = media.media_tracks
      assert media.source_path == Path.dirname(placed)
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
                 "The Way of Kings.m4b"
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
      assert placed1 == Path.join(folder, "The Way of Kings - Part 1 of 2.m4b")
      assert placed2 == Path.join(folder, "The Way of Kings - Part 2 of 2.m4b")
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
          on_import: :bring_in,
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
            "custody" => "managed",
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

    # A collision means two recordings rendered to one path, which is a
    # curation problem the operator has to see.
    test "refuses to overwrite something already at the destination" do
      %{item: item, root: root} = downloads_item()

      occupied =
        Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)", "The Way of Kings.m4b"])

      File.mkdir_p!(Path.dirname(occupied))
      File.write!(occupied, "already here")

      assert {:error, {:destination_exists, ^occupied}} = Inbox.import_item(item)
      assert File.read!(occupied) == "already here"
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
    test "a leave-in-place source is still adopted exactly where it lies" do
      %{item: item, source: source} =
        downloads_item(on_import: :leave_in_place, policy: nil)

      assert {:ok, media} = Inbox.import_item(item)

      media = Media.get_media!(media.id)
      assert media.custody == :external
      assert media.source_files == [source]
      assert File.exists?(source)
    end
  end

  defp downloads_item(opts \\ []) do
    on_import = Keyword.get(opts, :on_import, :bring_in)
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
    source = Path.join(release, "book.m4b")
    File.cp!(tagged_audio(), source)

    watched =
      insert(:source,
        on_import: on_import,
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

    %{item: item, root: root, source: source, watched: watched, downloads: downloads}
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
