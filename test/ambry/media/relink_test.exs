defmodule Ambry.Media.RelinkTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.Relink
  alias Ambry.Media.Scanner

  # Every plan that gets as far as proposing a destination needs a root that
  # actually exists on disk — the filesystem question is asked of the real
  # path, deliberately, so a fabricated one cannot answer it.
  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "ambry_test_files/relink-root-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    %{root: insert(:root, path: path)}
  end

  describe "plan/1 — finding the sources" do
    test "uses the recorded list when a recording has one" do
      media = legacy_media(:m4a, 2)

      plan = Relink.plan(media)

      assert plan.era == :recorded_list
      assert length(plan.sources) == 2
      assert Enum.all?(plan.sources, & &1.exists?)
    end

    # The 233 web-upload-era recordings have neither column, and their file
    # list only exists as whatever is sitting in the folder.
    test "falls back to listing the folder when nothing was recorded" do
      media = legacy_media(:m4a, 2)
      {:ok, media} = media |> Ecto.Changeset.change(%{source_files: []}) |> Repo.update()

      plan = Relink.plan(Media.get_media!(media.id))

      assert plan.era == :web_upload
      assert length(plan.sources) == 2
      assert plan.verdict == :ok
    end

    # The destination filenames are numbered by position, so the order the
    # sources come out in *is* the order the relinked book plays in. A
    # recorded list is not sorted — `Media.files/2` sorts on the way through,
    # which is the order the transcode read and therefore the order the
    # stored duration and every saved position belong to.
    test "reads a recorded list in play order, not the order it was stored in" do
      media = server_import_media(:m4a, 10)
      scrambled = Enum.reverse(media.legacy_source_files)

      {:ok, media} =
        media |> Ecto.Changeset.change(%{legacy_source_files: scrambled}) |> Repo.update()

      plan = Relink.plan(Media.get_media!(media.id))

      assert Enum.map(plan.sources, & &1.path) == Enum.sort(scrambled, NaturalOrder)
      assert plan.sources |> List.last() |> Map.fetch!(:path) =~ "10-sample"
    end

    test "refuses a recording whose files are gone" do
      media = legacy_media(:m4a, 1)
      media.source_files |> Enum.map(&Ambry.Paths.web_to_disk/1) |> Enum.each(&File.rm!/1)

      plan = Relink.plan(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "not on disk"))
    end

    test "refuses a recording that already has tracks" do
      media = legacy_media(:m4a, 1)
      {:ok, _scanned} = Scanner.scan(media)

      plan = Relink.plan(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "already has 1 track"))
    end
  end

  describe "plan/1 — the duration gate" do
    test "accepts sources that agree with the stored duration" do
      media = legacy_media(:m4a, 1)

      plan = Relink.plan(media)

      assert plan.verdict == :ok
      assert_in_delta plan.drift, 0.0, 0.1
    end

    # The case this whole gate exists for: the recorded path still resolves,
    # but the file at it is not the one that was transcoded. Measured in
    # production as a source replaced in place by a corrected re-download.
    test "refuses when the file at the path is not the file that was transcoded" do
      media = legacy_media(:m4a, 1)

      {:ok, media} =
        media |> Ecto.Changeset.change(%{duration: Decimal.new("9999.0")}) |> Repo.update()

      plan = Relink.plan(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "may not be the file that was transcoded"))
    end

    test "refuses a recording with no stored duration to check against" do
      media = legacy_media(:m4a, 1)
      {:ok, media} = media |> Ecto.Changeset.change(%{duration: nil}) |> Repo.update()

      plan = Relink.plan(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "no stored duration"))
    end
  end

  describe "tolerance/1" do
    # ffmpeg's concat accumulates ~65ms of mp3 frame padding per boundary, so
    # the window has to grow with the file count. A flat number wide enough
    # for a 63-file recording would wave through a wrong single file.
    test "is a floor for a single file" do
      assert Relink.tolerance(1) == 2.0
    end

    test "grows with the number of file boundaries" do
      assert Relink.tolerance(63) > 6.0
      assert Relink.tolerance(63) > Relink.tolerance(42)
      assert Relink.tolerance(42) > Relink.tolerance(10)
    end

    test "never drops below the floor for small counts" do
      assert Relink.tolerance(2) == 2.0
    end
  end

  describe "plan/1 — the destination" do
    test "refuses when there is no library root to place into" do
      Repo.delete_all(Ambry.Library.Root)
      media = legacy_media(:m4a, 1)

      plan = Relink.plan(media)

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "no library root"))
    end

    test "proposes a destination under the root, named by the template", %{root: root} do
      media = legacy_media(:m4a, 1)

      plan = Relink.plan(media)

      assert plan.verdict == :ok
      assert plan.root.id == root.id
      assert [destination] = plan.destinations
      assert String.starts_with?(destination, root.path)
      # Fixtures and the test root share a filesystem, so this is the
      # hardlink branch. The other one is a copy, never a move: the delete
      # half of a move is what would make a relink one-way, and the
      # upload-era originals are the only copy there is.
      assert plan.policy == :hardlink
      # the per-recording token is what keeps two readings of one book apart
      assert destination =~ Media.Media.filename_token(media)
    end

    # `hardlinkable?/2` answers `{:ok, boolean} | {:error, reason}` despite its
    # name, and an unmounted root is the error. Treated as a plain boolean the
    # tuple is truthy, so a destination nothing can even stat proposes a
    # hardlink — a failure and an answer looking alike, which is the oldest
    # rule here. Caught by spot-checking against a restored production copy.
    test "refuses rather than guessing when the root cannot be stat'd" do
      Repo.delete_all(Ambry.Library.Root)
      insert(:root, path: "/nonexistent/unmounted/root")
      media = legacy_media(:m4a, 1)

      plan = Relink.plan(media)

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "share a filesystem"))
      refute plan.policy
    end
  end

  describe "candidates/0" do
    test "lists recordings without tracks and skips those with them" do
      legacy = legacy_media(:m4a, 1)
      direct_play = legacy_media(:m4a, 1)
      {:ok, _} = Scanner.scan(direct_play)

      ids = Enum.map(Relink.candidates(), & &1.id)

      assert legacy.id in ids
      refute direct_play.id in ids
    end
  end

  describe "relink/1" do
    test "places the sources into the root and scans them into tracks", %{root: root} do
      media = legacy_media(:m4a, 2)

      assert {:ok, relinked, _plan} = Relink.relink(media)

      assert relinked.library_root_id == root.id
      assert length(relinked.media_tracks) == 2

      assert Enum.all?(relinked.source_files, &(not String.starts_with?(&1, "/")))
      assert Enum.all?(relinked.media_tracks, &(&1.library_root_id == root.id))

      for file <- relinked.source_files do
        assert File.regular?(Path.join(root.path, file))
      end
    end

    # The whole point of placing before deleting anything: the reclaim's first
    # half only ever adds, so it is undone by removing what it added.
    test "leaves the originals, the artifacts and the status alone" do
      media = legacy_media(:m4a, 1)
      originals = Enum.map(media.source_files, &Ambry.Paths.web_to_disk/1)

      assert {:ok, relinked, _plan} = Relink.relink(media)

      assert Enum.all?(originals, &File.regular?/1)
      assert relinked.status == media.status
      assert relinked.mp4_path == media.mp4_path
      assert relinked.mpd_path == media.mpd_path
      assert relinked.hls_path == media.hls_path
    end

    # Provenance that a placed recording is forbidden to carry
    # (`media_legacy_source_files_quarantined`). What it recorded is why the
    # inbox ledger has to compare content and not only paths.
    test "clears the legacy provenance a placed recording may not keep" do
      media = server_import_media(:m4a, 1)

      assert {:ok, relinked, _plan} = Relink.relink(media)

      assert relinked.legacy_source_files == nil
      assert length(relinked.media_tracks) == 1
    end

    test "refuses whatever the plan refuses, and writes nothing", %{root: root} do
      media = legacy_media(:m4a, 1)

      {:ok, media} =
        media |> Ecto.Changeset.change(%{duration: Decimal.new("9999.0")}) |> Repo.update()

      assert {:error, plan} = Relink.relink(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert File.ls!(root.path) == []
      assert Media.get_media!(media.id).library_root_id == nil
    end

    # Placement is all-or-nothing per recording, and a half-placed recording
    # is a book that plays up to chapter one and stops.
    test "leaves nothing behind when a file can't be placed", %{root: root} do
      media = legacy_media(:m4a, 2)
      plan = Relink.plan(media)
      [_first, second] = plan.destinations

      File.mkdir_p!(Path.dirname(second))
      File.write!(second, "in the way")

      assert {:error, {:placement_failed, {:destination_exists, ^second}}} = Relink.relink(media)

      assert Media.get_media!(media.id).library_root_id == nil
      placed = root.path |> Path.join("**/*") |> Path.wildcard() |> Enum.filter(&File.regular?/1)
      assert placed == [second]
    end

    # Not a guard anyone wrote: a relinked recording has tracks, and a
    # recording with tracks is not a candidate.
    test "refuses a recording it already relinked" do
      media = legacy_media(:m4a, 1)

      assert {:ok, _relinked, _plan} = Relink.relink(media)
      assert {:error, plan} = Relink.relink(Media.get_media!(media.id))

      assert plan.verdict == :refused
      assert Enum.any?(plan.problems, &(&1 =~ "already has 1 track"))
    end
  end

  defp legacy_media(type, count) do
    :media
    |> build(book: build(:book))
    |> with_copied_source_files(type, count)
    |> insert()
    |> then(&Media.get_media!(&1.id))
    |> give_it_the_transcode_duration()
  end

  # The 204 server-import-era recordings: no recorded `source_files` at all,
  # and absolute paths into a downloads folder that is a source, not a root.
  defp server_import_media(type, count) do
    media = legacy_media(type, count)

    {:ok, media} =
      media
      |> Ecto.Changeset.change(%{
        source_files: [],
        legacy_source_files: Enum.map(media.source_files, &Ambry.Paths.web_to_disk/1)
      })
      |> Repo.update()

    Media.get_media!(media.id)
  end

  # A legacy recording's stored duration came from its transcode, which is
  # what the gate compares against. Scanning to learn it and then throwing the
  # tracks away is the only way to get a fixture whose stored duration is
  # honestly derived from its files.
  defp give_it_the_transcode_duration(media) do
    {:ok, scanned} = Scanner.scan(media)
    Repo.delete_all(from(t in Media.MediaTrack, where: t.media_id == ^media.id))

    Media.get_media!(scanned.id)
  end
end
