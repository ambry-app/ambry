defmodule Ambry.Media.ReconciliationTest do
  @moduledoc """
  Noticing that a recording's files stopped being there.

  The rule the whole module is built around: recording what's wrong, never
  acting on it. Files vanish for ordinary reasons — a torrent removed, a NAS
  unplugged this morning — and none of them mean the recording should be
  deleted or downgraded.
  """
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.Reconciliation
  alias Ambry.Repo

  describe "reconcile/1" do
    test "stamps a recording whose track file has vanished" do
      %{media: media, file: file} = direct_play_media()
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(media)
      assert %DateTime{} = Repo.reload(media).missing_since
    end

    test "leaves a recording whose files are all present" do
      %{media: media} = direct_play_media()

      assert {:ok, :unchanged} = Reconciliation.reconcile(media)
      assert is_nil(Repo.reload(media).missing_since)
    end

    # The reason this is a timestamp rather than a status: an unplugged disk
    # comes back, and when it does the recording must simply be fine again.
    test "clears the mark when the files come back" do
      %{media: media, file: file} = direct_play_media()
      contents = File.read!(file)
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(media)

      File.write!(file, contents)
      media = Repo.reload(media) |> Repo.preload(:media_tracks)

      assert {:ok, :healed} = Reconciliation.reconcile(media)
      assert is_nil(Repo.reload(media).missing_since)
    end

    # Overwriting `status` would destroy what the recording was before, so
    # remounting a disk holding 300 recordings would leave no way to know
    # which were ready and which were still pending.
    test "never touches the recording's status" do
      %{media: media, file: file} = direct_play_media(status: :ready)
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(media)
      assert Repo.reload(media).status == :ready
    end

    test "doesn't re-stamp a recording that is already marked" do
      %{media: media, file: file} = direct_play_media()
      File.rm!(file)

      assert {:ok, :missing} = Reconciliation.reconcile(media)
      marked = media |> Repo.reload() |> Repo.preload(:media_tracks)
      first = marked.missing_since

      assert {:ok, :unchanged} = Reconciliation.reconcile(marked)
      assert Repo.reload(media).missing_since == first
    end

    # A pending recording that was never scanned has no playable files at
    # all, which is not the same as having lost them.
    test "a recording with nothing to play yet isn't missing" do
      media = insert(:media, book: build(:book), mp4_path: nil, hls_path: nil, mpd_path: nil)
      media = Repo.preload(media, :media_tracks)

      assert Reconciliation.missing_files(media) == []
      assert {:ok, :unchanged} = Reconciliation.reconcile(media)
    end

    # A legacy recording whose originals were cleaned up still plays fine.
    # Calling it missing would cry wolf on exactly the recordings Phase 4 is
    # going to reclaim.
    test "ignores source files that only ever fed a transcode" do
      %{media: media} = legacy_media()
      File.rm_rf!(media.source_path)

      assert Reconciliation.missing_files(Repo.preload(media, :media_tracks)) == []
    end

    test "notices a legacy recording whose transcoded output has vanished" do
      %{media: media, mp4: mp4} = legacy_media()
      File.rm!(mp4)

      assert {:ok, :missing} = Reconciliation.reconcile(Repo.preload(media, :media_tracks))
    end
  end

  describe "reconcile_all/0" do
    test "counts what it found and what came back" do
      %{media: gone, file: file} = direct_play_media()
      %{media: _fine} = direct_play_media()
      File.rm!(file)

      assert {:ok, %{checked: 2, missing: 1, healed: 0}} = Reconciliation.reconcile_all()
      assert %DateTime{} = Repo.reload(gone).missing_since

      File.write!(file, "audio")
      assert {:ok, %{checked: 2, missing: 0, healed: 1}} = Reconciliation.reconcile_all()
      assert is_nil(Repo.reload(gone).missing_since)
    end

    # A sweep that deleted anything would be a disaster the first time a NAS
    # was slow to mount.
    test "never deletes a record" do
      %{media: media, file: file} = direct_play_media()
      File.rm!(file)

      assert {:ok, _counts} = Reconciliation.reconcile_all()
      assert Media.get_media!(media.id)
    end
  end

  defp direct_play_media(opts \\ []) do
    dir = new_dir("recon")
    file = Path.join(dir, "book.m4b")
    File.write!(file, "audio")

    media =
      insert(:media,
        book: build(:book),
        status: Keyword.get(opts, :status, :pending),
        custody: :managed,
        source_path: dir,
        source_files: [file],
        mp4_path: nil,
        hls_path: nil,
        mpd_path: nil,
        media_tracks: [build(:media_track, path: file)]
      )

    %{media: Repo.preload(media, :media_tracks), file: file, dir: dir}
  end

  defp legacy_media do
    dir = new_dir("legacy")
    source = Path.join(dir, "original.mp3")
    File.write!(source, "original")

    filename = "#{Ecto.UUID.generate()}.mp4"
    mp4 = Ambry.Paths.media_disk_path(filename)
    File.mkdir_p!(Path.dirname(mp4))
    File.write!(mp4, "transcoded")

    media =
      insert(:media,
        book: build(:book),
        status: :ready,
        source_path: dir,
        source_files: [source],
        mp4_path: "/uploads/media/#{filename}",
        hls_path: nil,
        mpd_path: nil
      )

    %{media: media, mp4: mp4, source: source}
  end

  defp new_dir(prefix) do
    dir = Ambry.Paths.source_media_disk_path("#{prefix}-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    dir
  end
end
