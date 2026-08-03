defmodule Ambry.Media.ScannerTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner

  describe "scan/1" do
    test "records what the file is, without touching it" do
      media = scannable_media(:m4a)
      [source_file] = media.source_files
      before = File.stat!(source_file)

      assert {:ok, media} = Scanner.scan(media)

      assert [%MediaTrack{} = track] = Media.get_media!(media.id).media_tracks
      assert track.index == 0
      assert track.path == source_file
      assert track.size == before.size
      assert track.codec == "aac"
      assert track.mime == "audio/mp4"
      assert track.format =~ "mp4"
      assert Decimal.equal?(track.start_offset, 0)

      assert File.stat!(source_file).size == before.size
    end

    test "gives the media the track's duration" do
      media = scannable_media(:m4a)

      assert {:ok, media} = Scanner.scan(media)

      assert Decimal.compare(media.duration, "3.8") == :gt
      assert Decimal.compare(media.duration, "3.9") == :lt
    end

    test "trusts an indexed container's duration" do
      media = scannable_media(:m4a)

      assert {:ok, media} = Scanner.scan(media)

      assert [%MediaTrack{seek_accuracy: :exact}] = Media.get_media!(media.id).media_tracks
    end

    test "decode-counts a container that can't be trusted" do
      media = scannable_media(:mp3)

      assert {:ok, media} = Scanner.scan(media)

      assert [track] = Media.get_media!(media.id).media_tracks
      assert track.codec == "mp3"
      assert track.mime == "audio/mpeg"
      # the sample is CBR, so the claimed duration holds up and seeking is fine
      assert track.seek_accuracy == :exact
      assert Decimal.compare(track.duration, "3.7") == :gt
      assert Decimal.compare(track.duration, "3.9") == :lt
    end

    test "scans every container direct-play serves" do
      for type <- [:m4a, :mp3, :flac, :ogg, :opus, :wav] do
        media = scannable_media(type)

        assert {:ok, media} = Scanner.scan(media), "couldn't scan a #{type} file"
        assert [%MediaTrack{}] = Media.get_media!(media.id).media_tracks
      end
    end

    test "replaces the tracks of a media scanned before" do
      media = scannable_media(:m4a)

      assert {:ok, _media} = Scanner.scan(media)
      media = Media.get_media!(media.id)
      assert {:ok, media} = Scanner.scan(media)

      assert [%MediaTrack{index: 0}] = Media.get_media!(media.id).media_tracks
    end

    test "does not publish the media" do
      media = scannable_media(:m4a)

      assert {:ok, media} = Scanner.scan(media)

      assert media.status == :pending
    end

    test "refuses a multi-file recording rather than guessing" do
      media = scannable_media(:mp3, 3)

      assert {:error, :multi_file_unsupported} = Scanner.scan(media)
      assert Media.get_media!(media.id).media_tracks == []
    end

    test "reports a media with nothing to scan" do
      media = insert(:media, book: build(:book))

      assert {:error, :no_audio_files} = Scanner.scan(media)
    end

    test "reports a file that has gone missing" do
      media = scannable_media(:m4a)
      media.source_files |> hd() |> File.rm!()

      assert {:error, :enoent} = Scanner.scan(media)
    end
  end

  describe "scan/1 chapters" do
    test "takes embedded chapter markers when the media has none" do
      media = chaptered_media()

      assert {:ok, media} = Scanner.scan(media)

      assert [first, second] = media.chapters
      assert first.title == "Opening Credits"
      assert Decimal.equal?(first.time, 0)
      assert second.title == "Chapter One"
      assert Decimal.compare(second.time, 0) == :gt
    end

    test "never overwrites chapters the operator already has" do
      media = chaptered_media(chapters: [%{time: Decimal.new(0), title: "Curated"}])

      assert {:ok, media} = Scanner.scan(media)

      assert [%{title: "Curated"}] = media.chapters
    end

    test "leaves chapters alone when the file has none" do
      media = scannable_media(:m4a)

      assert {:ok, media} = Scanner.scan(media)

      assert media.chapters == []
    end
  end

  defp scannable_media(type, count \\ 1, attrs \\ []) do
    :media
    |> build([book: build(:book)] ++ attrs)
    |> with_copied_source_files(type, count)
    |> insert()
    |> then(&Media.get_media!(&1.id))
  end

  # ffmpeg is the only thing around that writes chapter atoms, so the fixture
  # is built the same way a real m4b gets them.
  defp chaptered_media(attrs \\ []) do
    media = scannable_media(:m4a, 1, attrs)
    [source_file] = media.source_files

    metadata_path = Path.join(Path.dirname(source_file), "chapters.txt")

    File.write!(metadata_path, """
    ;FFMETADATA1
    [CHAPTER]
    TIMEBASE=1/1000
    START=0
    END=2000
    title=Opening Credits
    [CHAPTER]
    TIMEBASE=1/1000
    START=2000
    END=3800
    title=Chapter One
    """)

    chaptered_path = Path.join(Path.dirname(source_file), "chaptered.m4a")

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-i",
        source_file,
        "-i",
        metadata_path,
        "-map_metadata",
        "1",
        "-c",
        "copy",
        "-v",
        "quiet",
        chaptered_path
      ])

    File.rm!(source_file)

    {:ok, media} = Media.update_media(media, %{source_files: [chaptered_path]})
    Media.get_media!(media.id)
  end
end
