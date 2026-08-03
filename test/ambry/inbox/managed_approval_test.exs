defmodule Ambry.Inbox.ManagedApprovalTest do
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

  describe "approving from a downloads location" do
    test "hardlinks into the library under the naming template" do
      %{item: item, root: root, source: source} = downloads_item()

      assert {:ok, media} = Inbox.approve_item(item)

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

      assert {:ok, media} = Inbox.approve_item(item)

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

      assert {:ok, media} = Inbox.approve_item(item)

      assert [placed] = Media.get_media!(media.id).source_files
      assert File.exists?(placed)
      # the source is removed only after the records committed
      refute File.exists?(source)
    end

    test "copies when asked to, duplicating deliberately" do
      %{item: item, source: source} = downloads_item(policy: :copy)

      assert {:ok, media} = Inbox.approve_item(item)

      assert [placed] = Media.get_media!(media.id).source_files
      assert File.exists?(source)
      assert {:ok, %{links: 1}} = File.stat(placed)
    end

    test "marks the item approved and links it to what it became" do
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.approve_item(item)

      {[item], false} = Inbox.list_items()
      assert item.status == :approved
      assert item.media_id == media.id
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

        assert {:error, {:cross_filesystem, ^source, _destination}} = Inbox.approve_item(item)

        # library untouched, item still queued
        assert {[item], false} = Inbox.list_items()
        assert item.status == :pending
        assert {[], false} = Media.list_media()
      end
    end

    test "refuses when there is no library root to import into" do
      %{item: item} = downloads_item(root: :none)

      assert {:error, :no_library_root} = Inbox.approve_item(item)

      {[item], false} = Inbox.list_items()
      assert item.status == :pending
    end

    # With several roots the choice is about which NAS, and therefore about
    # whether hardlinking is possible at all. Guessing is not acceptable.
    test "refuses when several roots exist and none was chosen" do
      %{item: item} = downloads_item()
      insert(:location, kind: :library_root, import_policy: nil, path: new_dir("second-root"))

      assert {:error, :ambiguous_library_root} = Inbox.approve_item(item)
    end

    test "uses the explicitly chosen root when there are several" do
      %{item: item, location: location} = downloads_item()

      chosen =
        insert(:location, kind: :library_root, import_policy: nil, path: new_dir("chosen-root"))

      {:ok, _location} = Library.update_location(location, %{target_root_id: chosen.id})

      assert {:ok, media} = Inbox.approve_item(Repo.reload(item))

      assert [placed] = Media.get_media!(media.id).source_files
      assert String.starts_with?(placed, chosen.path)
    end

    # A collision means two recordings rendered to one path, which is a
    # curation problem the operator has to see.
    test "refuses to overwrite something already at the destination" do
      %{item: item, root: root} = downloads_item()

      occupied =
        Path.join([root, "Brandon Sanderson", "The Way of Kings (2010)", "The Way of Kings.m4b"])

      File.mkdir_p!(Path.dirname(occupied))
      File.write!(occupied, "already here")

      assert {:error, {:destination_exists, ^occupied}} = Inbox.approve_item(item)
      assert File.read!(occupied) == "already here"
    end
  end

  describe "publishing on approval" do
    # An approved recording is finished. Leaving it pending forever was the
    # gap that made the inbox produce records nothing could ever see.
    test "publishes when the switch is on" do
      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.approve_item(item)
      assert Media.get_media!(media.id).status == :ready
    end

    # The whole point of the switch: the server must never hand a client a
    # direct-play recording before the fleet can play one.
    test "waits in pending when the switch is off" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      %{item: item} = downloads_item()

      assert {:ok, media} = Inbox.approve_item(item)
      assert Media.get_media!(media.id).status == :pending
    end

    test "turning the switch on later releases what was waiting" do
      {:ok, _setting} = Settings.set_direct_play_publishing(false)
      %{item: item} = downloads_item()
      {:ok, media} = Inbox.approve_item(item)

      {:ok, _setting} = Settings.set_direct_play_publishing(true)
      assert {:ok, %{published: 1}} = Media.publish_pending_direct_play()

      assert Media.get_media!(media.id).status == :ready
    end
  end

  describe "other locations" do
    test "an external collection is still adopted exactly where it lies" do
      %{item: item, source: source} =
        downloads_item(kind: :external_collection, policy: nil)

      assert {:ok, media} = Inbox.approve_item(item)

      media = Media.get_media!(media.id)
      assert media.custody == :external
      assert media.source_files == [source]
      assert File.exists?(source)
    end
  end

  defp downloads_item(opts \\ []) do
    kind = Keyword.get(opts, :kind, :downloads)
    policy = Keyword.get(opts, :policy, :hardlink)

    root =
      case Keyword.get(opts, :root, :default) do
        :none -> nil
        :default -> new_dir("root")
        path -> path
      end

    if root do
      insert(:location, kind: :library_root, import_policy: nil, path: root, name: "Library")
    end

    downloads = new_dir("downloads")
    release = Path.join(downloads, "The Way of Kings [M4B]")
    File.mkdir_p!(release)
    source = Path.join(release, "book.m4b")
    File.cp!(tagged_audio(), source)

    location =
      insert(:location,
        kind: kind,
        import_policy: policy,
        path: downloads,
        name: "Downloads #{Ecto.UUID.generate()}"
      )

    {:ok, _counts} = Inbox.discover(location)
    {[item], false} = Inbox.list_items()
    {:ok, item} = Inbox.probe_item(item)

    # Approval executes a resolved draft, so these tests arrange one the way
    # the import form would leave it — what they're actually about is what
    # happens to the bytes afterwards.
    item = settle(item)

    %{item: item, root: root, source: source, location: location, downloads: downloads}
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
