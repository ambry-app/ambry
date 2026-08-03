defmodule Ambry.Media.Scanner.ProbeTest do
  use Ambry.DataCase

  alias Ambry.Media.Scanner.Probe

  describe "run/1" do
    test "reports the container and codec as they are" do
      assert {:ok, probe} = Probe.run(valid_audio(:m4a))

      assert probe.format == "mov,mp4,m4a,3gp,3g2,mj2"
      assert probe.codec == "aac"
      assert probe.mime == "audio/mp4"
      assert probe.size == File.stat!(valid_audio(:m4a)).size
    end

    test "identifies each container direct-play serves" do
      for {type, codec, mime} <- [
            {:m4a, "aac", "audio/mp4"},
            {:mp3, "mp3", "audio/mpeg"},
            {:flac, "flac", "audio/flac"},
            {:ogg, "vorbis", "audio/ogg"},
            {:opus, "opus", "audio/ogg"},
            {:wav, "pcm_s16le", "audio/wav"}
          ] do
        assert {:ok, probe} = Probe.run(valid_audio(type))
        assert probe.codec == codec, "wrong codec for #{type}: #{probe.codec}"
        assert probe.mime == mime, "wrong mime for #{type}: #{probe.mime}"
        assert Decimal.compare(probe.duration, 0) == :gt
      end
    end

    test "returns an error for a file that isn't there" do
      assert {:error, :enoent} = Probe.run("/nonexistent/book.m4b")
    end

    @tag :capture_log
    test "returns an error for a file with no audio in it" do
      path = Path.join(tmp_dir(), "not-audio.mp3")
      File.write!(path, "this is not an mp3")

      assert {:error, _reason} = Probe.run(path)
    end
  end

  describe "run/1 seek accuracy" do
    test "an indexed container seeks exactly" do
      assert {:ok, probe} = Probe.run(valid_audio(:m4a))

      assert probe.seek_accuracy == :exact
    end

    test "a VBR mp3 with a Xing index seeks exactly" do
      assert {:ok, probe} = :xing |> vbr_mp3() |> Probe.run()

      assert probe.seek_accuracy == :exact
      # the index tells the truth, so the decoded length agrees with it
      assert_in_seconds(probe.duration, 30, 1)
    end

    test "a VBR mp3 without one is flagged as approximate" do
      assert {:ok, probe} = :no_xing |> vbr_mp3() |> Probe.run()

      assert probe.seek_accuracy == :approximate
      # and the duration is the decoded one, not the container's ~5% guess
      assert_in_seconds(probe.duration, 30, 1)
    end
  end

  defp assert_in_seconds(actual, expected, tolerance) do
    assert actual |> Decimal.sub(expected) |> Decimal.abs() |> Decimal.compare(tolerance) != :gt,
           "expected #{actual} to be within #{tolerance}s of #{expected}"
  end

  # Two very different 15s halves, encoded at the lowest LAME quality, so the
  # bitrate really does vary and a missing Xing header really does mislead
  # whoever reads the first frame.
  defp vbr_mp3(:xing), do: build_vbr_mp3()

  defp vbr_mp3(:no_xing) do
    source = build_vbr_mp3()
    stripped = Path.join(tmp_dir(), "vbr-no-xing-#{System.unique_integer([:positive])}.mp3")

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-i",
        source,
        "-c",
        "copy",
        "-write_xing",
        "0",
        stripped
      ])

    stripped
  end

  defp build_vbr_mp3 do
    path = Path.join(tmp_dir(), "vbr-#{System.unique_integer([:positive])}.mp3")

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=200:duration=15",
        "-f",
        "lavfi",
        "-i",
        "anoisesrc=duration=15:amplitude=0.8",
        "-filter_complex",
        "[0][1]concat=n=2:v=0:a=1",
        "-codec:a",
        "libmp3lame",
        "-q:a",
        "9",
        path
      ])

    path
  end

  defp tmp_dir do
    dir = Ambry.Paths.source_media_disk_path("probe-test")
    File.mkdir_p!(dir)
    dir
  end
end
