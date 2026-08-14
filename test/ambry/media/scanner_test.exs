defmodule Ambry.Media.ScannerTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner

  describe "scan/1" do
    test "records what the file is, without touching it" do
      media = scannable_media(:m4a)
      [source_file] = media.source_files
      source_file_on_disk = Ambry.Paths.web_to_disk(source_file)
      before = File.stat!(source_file_on_disk)

      assert {:ok, media} = Scanner.scan(media)

      assert [%MediaTrack{} = track] = Media.get_media!(media.id).media_tracks
      assert track.index == 0
      assert track.path == source_file
      assert track.size == before.size
      assert track.codec == "aac"
      assert track.mime == "audio/mp4"
      assert track.format =~ "mp4"
      assert Decimal.equal?(track.start_offset, 0)

      assert File.stat!(source_file_on_disk).size == before.size
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

    test "lays a multi-file recording end to end on one timeline" do
      media = scannable_media(:mp3, 3)

      assert {:ok, media} = Scanner.scan(media)

      tracks =
        media.id
        |> Media.get_media!()
        |> Map.fetch!(:media_tracks)
        |> Enum.sort_by(& &1.index)

      assert [%MediaTrack{index: 0}, %MediaTrack{index: 1}, %MediaTrack{index: 2}] = tracks

      # Each track starts where the previous one ended, with no gap and no
      # overlap, and the book is as long as all of them together.
      Enum.reduce(tracks, Decimal.new(0), fn track, expected_offset ->
        assert Decimal.equal?(track.start_offset, expected_offset)
        Decimal.add(expected_offset, track.duration)
      end)

      assert Decimal.equal?(
               media.duration,
               Enum.reduce(tracks, Decimal.new(0), &Decimal.add(&2, &1.duration))
             )
    end

    test "plays a multi-file recording in natural order, whatever order the files were recorded in" do
      media = scannable_media(:mp3, 12)

      # `File.ls/1` gives no order at all, and a recording old enough to
      # predate `source_files` is read straight off the filesystem. A plain
      # string sort would put "10-sample" before "2-sample" and shuffle the
      # book.
      {:ok, media} =
        media
        |> Ecto.Changeset.change(%{source_files: Enum.shuffle(media.source_files)})
        |> Repo.update()

      assert {:ok, _media} = Scanner.scan(media)

      names =
        media.id
        |> Media.get_media!()
        |> Map.fetch!(:media_tracks)
        |> Enum.sort_by(& &1.index)
        |> Enum.map(&Path.basename(&1.path))

      assert names == Enum.sort(names, NaturalOrder)
      assert hd(names) == "1-sample.mp3"
      assert names |> Enum.at(1) == "2-sample.mp3"
    end

    test "reports a media with nothing to scan" do
      media = insert(:media, book: build(:book))

      assert {:error, :no_audio_files} = Scanner.scan(media)
    end

    test "reports a file that has gone missing" do
      media = scannable_media(:m4a)
      media.source_files |> hd() |> Ambry.Paths.web_to_disk() |> File.rm!()

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

  describe "tags/1" do
    test "reads embedded metadata off a real file" do
      media = tagged_media()

      assert {:ok, tags} = Scanner.tags(media)

      assert tags.book_title == "The Way of Kings"
      assert tags.authors == ["Brandon Sanderson"]
      assert tags.narrators == ["Michael Kramer", "Kate Reading"]
      assert tags.series == "The Stormlight Archive"
      assert Decimal.equal?(tags.series_number, 1)
      assert tags.asin == "B003ZWFO7E"
      assert tags.published == ~D[2010-08-31]
      assert tags.published_format == :full
    end

    test "notices embedded cover art" do
      media = media_with_cover_art()

      assert {:ok, tags} = Scanner.tags(media)
      assert tags.has_cover_art
      assert tags.book_title == "Illustrated Edition"
    end

    test "reports no cover art when there is none" do
      media = tagged_media()

      assert {:ok, tags} = Scanner.tags(media)
      refute tags.has_cover_art
    end

    test "an untagged file yields an empty struct, not an error" do
      media = scannable_media(:m4a)

      assert {:ok, tags} = Scanner.tags(media)
      refute Ambry.Media.Scanner.Tags.any?(tags)
    end

    test "reports a media with nothing to read" do
      media = insert(:media, book: build(:book))

      assert {:error, :no_audio_files} = Scanner.tags(media)
    end
  end

  # Tagged the way a real rip is: freeform MP4 atoms for the things the
  # container has no standard place for (ASIN, series), narrator in composer.
  defp tagged_media do
    retag(["-movflags", "use_metadata_tags"], [
      "album=The Way of Kings",
      "artist=Brandon Sanderson",
      "composer=Michael Kramer, Kate Reading",
      "SERIES=The Stormlight Archive",
      "SERIES-PART=1",
      "ASIN=B003ZWFO7E",
      "date=2010-08-31"
    ])
  end

  # Separate fixture because ffmpeg's mov muxer drops the attached-pic stream
  # when asked to write freeform atoms — a quirk of *writing* these files, not
  # of reading them, so real rips carry both happily.
  defp media_with_cover_art do
    retag(["-cover"], ["album=Illustrated Edition"])
  end

  defp retag(flags, metadata) do
    media = scannable_media(:m4a)
    [source_file] = media.source_files
    source_file = Ambry.Paths.web_to_disk(source_file)
    dir = Path.dirname(source_file)
    tagged_path = Path.join(dir, "tagged.m4b")

    {inputs, flags} = cover_args(flags, dir, source_file)

    args =
      ["-v", "quiet"] ++
        inputs ++
        ["-c", "copy"] ++
        flags ++
        Enum.flat_map(metadata, &["-metadata", &1]) ++
        [tagged_path]

    {_output, 0} = System.cmd("ffmpeg", args)

    File.rm!(source_file)

    {:ok, media} =
      Media.update_media(media, %{source_files: [Ambry.Paths.disk_to_web(tagged_path)]})

    Media.get_media!(media.id)
  end

  defp cover_args(["-cover"], dir, source_file) do
    cover = Path.join(dir, "cover.jpg")

    {_output, 0} =
      System.cmd("ffmpeg", ~w(-v quiet -f lavfi -i color=red:s=64x64:d=1 -frames:v 1) ++ [cover])

    {["-i", source_file, "-i", cover, "-map", "0:a", "-map", "1:v"],
     ["-disposition:v", "attached_pic"]}
  end

  defp cover_args(flags, _dir, source_file), do: {["-i", source_file], flags}

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
    source_file = Ambry.Paths.web_to_disk(source_file)

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

    {:ok, media} =
      Media.update_media(media, %{source_files: [Ambry.Paths.disk_to_web(chaptered_path)]})

    Media.get_media!(media.id)
  end
end
