defmodule Ambry.Media.Relink.ConsoleTest do
  use Ambry.DataCase

  import ExUnit.CaptureIO

  alias Ambry.Media
  alias Ambry.Media.Relink
  alias Ambry.Media.Relink.Console
  alias Ambry.Media.Scanner

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "ambry_test_files/console-root-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    %{root: insert(:root, path: path)}
  end

  describe "report/1" do
    test "prints a plan per recording and writes nothing", %{root: root} do
      media = legacy_media(:m4a, 1)

      {summary, output} = with_output(fn -> Console.report() end)

      assert summary.planned == 1
      assert summary.ok == 1
      assert summary.policies == %{hardlink: 1}

      assert output =~ "[#{media.id}]"
      assert output =~ "verdict=ok"
      assert output =~ "stored="

      assert File.ls!(root.path) == []
      assert Media.get_media!(media.id).library_root_id == nil
    end

    test "says why it refused, rather than leaving the line out" do
      media = legacy_media(:m4a, 1)
      media.source_files |> Enum.map(&Ambry.Paths.web_to_disk/1) |> Enum.each(&File.rm!/1)

      {summary, output} = with_output(fn -> Console.report() end)

      assert summary.refused == 1
      assert summary.refused_ids == [media.id]
      assert output =~ "not on disk"
    end

    # A 63-file recording is 63 near-identical lines. The tail is summarized
    # rather than dropped quietly: a truncation nobody is told about reads as
    # completeness.
    test "summarizes the tail of a long file list instead of printing it" do
      _media = legacy_media(:m4a, 5)

      {_summary, output} = with_output(fn -> Console.report() end)

      assert output =~ "- 003.m4b"
      refute output =~ "- 004.m4b"
      assert output =~ "and 2 more"
    end

    test "selects by era" do
      upload_era = legacy_media(:m4a, 1)
      {:ok, _} = upload_era |> Ecto.Changeset.change(%{source_files: []}) |> Repo.update()
      recorded = legacy_media(:m4a, 1)

      {summary, output} = with_output(fn -> Console.report(era: :recorded_list) end)

      assert summary.planned == 1
      assert output =~ "[#{recorded.id}]"
      refute output =~ "[#{upload_era.id}]"
    end

    test "takes a limit, oldest first" do
      first = legacy_media(:m4a, 1)
      second = legacy_media(:m4a, 1)

      {summary, output} = with_output(fn -> Console.report(limit: 1) end)

      assert summary.planned == 1
      assert output =~ "[#{first.id}]"
      refute output =~ "[#{second.id}]"
    end

    # A named recording is answered about, not filtered out: "it already has
    # tracks" is the answer, and silence isn't.
    test "plans a named recording even when it isn't a candidate" do
      media = legacy_media(:m4a, 1)
      {:ok, _scanned} = Scanner.scan(media)

      {summary, output} = with_output(fn -> Console.report(ids: [media.id]) end)

      assert summary.refused == 1
      assert output =~ "already has 1 track"
    end

    test "says so when a named recording doesn't exist" do
      {summary, output} = with_output(fn -> Console.report(ids: [123_456]) end)

      assert summary.planned == 0
      assert output =~ "no such recording"
    end
  end

  describe "run/1" do
    test "dry-runs unless told twice", %{root: root} do
      media = legacy_media(:m4a, 1)

      {summary, output} = with_output(fn -> Console.run() end)

      assert summary.ok == 1
      assert output =~ "Nothing was written"

      assert File.ls!(root.path) == []
      assert Media.get_media!(media.id).library_root_id == nil
    end

    test "relinks when told twice, and says what it did", %{root: root} do
      media = legacy_media(:m4a, 2)

      {summary, output} = with_output(fn -> Console.run(dry_run: false) end)

      assert summary.relinked == 1
      assert summary.failed == 0
      assert summary.policies == %{hardlink: 1}
      assert output =~ "relinked: 2 track(s), hardlink"

      relinked = Media.get_media!(media.id)
      assert relinked.library_root_id == root.id
      assert length(relinked.media_tracks) == 2
    end

    test "reports a refusal and carries on to the next recording" do
      refused = legacy_media(:m4a, 1)
      refused.source_files |> Enum.map(&Ambry.Paths.web_to_disk/1) |> Enum.each(&File.rm!/1)
      relinkable = legacy_media(:m4a, 1)

      {summary, _output} = with_output(fn -> Console.run(dry_run: false) end)

      assert summary.refused == 1
      assert summary.refused_ids == [refused.id]
      assert summary.relinked == 1
      assert Media.get_media!(relinkable.id).library_root_id != nil
    end

    # A refusal is an expected outcome; an error means the tool is wrong about
    # the world, and finding that out four hundred times isn't more
    # information than finding it out once.
    test "stops at the first error" do
      blocked = legacy_media(:m4a, 1)
      untouched = legacy_media(:m4a, 1)

      [destination] = Relink.plan(blocked).destinations
      File.mkdir_p!(Path.dirname(destination))
      File.write!(destination, "in the way")

      {summary, output} = with_output(fn -> Console.run(dry_run: false) end)

      assert summary.failed == 1
      assert [{_id, {:placement_failed, _reason}}] = summary.failures
      assert output =~ "FAILED"
      assert output =~ "Stopped at the first error"

      assert Media.get_media!(untouched.id).library_root_id == nil
    end

    test "carries on past errors when told to" do
      blocked = legacy_media(:m4a, 1)
      relinkable = legacy_media(:m4a, 1)

      [destination] = Relink.plan(blocked).destinations
      File.mkdir_p!(Path.dirname(destination))
      File.write!(destination, "in the way")

      {summary, _output} =
        with_output(fn -> Console.run(dry_run: false, stop_on_error: false) end)

      assert summary.failed == 1
      assert summary.relinked == 1
      assert Media.get_media!(relinkable.id).library_root_id != nil
    end
  end

  defp with_output(fun) do
    result = make_ref()
    parent = self()

    output = capture_io(fn -> send(parent, {result, fun.()}) end)

    receive do
      {^result, value} -> {value, output}
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

  defp give_it_the_transcode_duration(media) do
    {:ok, scanned} = Scanner.scan(media)
    Repo.delete_all(from(t in Media.MediaTrack, where: t.media_id == ^media.id))

    Media.get_media!(scanned.id)
  end
end
