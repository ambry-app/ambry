defmodule Ambry.Media.ScannerTest do
  use Ambry.DataCase

  alias Ambry.Media
  alias Ambry.Media.Scanner

  describe "probe_all/1" do
    test "records what a file is, without touching it" do
      file = fixture_file(:m4a)
      before = File.stat!(file)

      assert {:ok, [probe]} = Scanner.probe_all([file])

      assert probe.path == file
      assert probe.size == before.size
      assert probe.codec == "aac"
      assert probe.mime == "audio/mp4"
      assert probe.format =~ "mp4"

      assert File.stat!(file).size == before.size
    end

    test "trusts an indexed container's duration" do
      assert {:ok, [%{seek_accuracy: :exact}]} = Scanner.probe_all([fixture_file(:m4a)])
    end

    test "decode-counts a container that can't be trusted" do
      assert {:ok, [probe]} = Scanner.probe_all([fixture_file(:mp3)])

      assert probe.codec == "mp3"
      assert probe.mime == "audio/mpeg"
      # the sample is CBR, so the claimed duration holds up and seeking is fine
      assert probe.seek_accuracy == :exact
      assert Decimal.compare(probe.duration, "3.7") == :gt
      assert Decimal.compare(probe.duration, "3.9") == :lt
    end

    test "probes every container direct-play serves" do
      for type <- [:m4a, :mp3, :flac, :ogg, :opus, :wav] do
        assert {:ok, [_probe]} = Scanner.probe_all([fixture_file(type)]),
               "couldn't probe a #{type} file"
      end
    end

    test "reports a file that has gone missing" do
      file = fixture_file(:m4a)
      File.rm!(file)

      assert {:error, :enoent} = Scanner.probe_all([file])
    end

    # One unreadable file in forty means every track after it sits at the
    # wrong offset, so a partial answer is worse than none.
    test "refuses the whole set when one file is unreadable" do
      good = fixture_file(:m4a)
      missing = Path.join(Path.dirname(good), "gone.m4a")

      assert {:error, :enoent} = Scanner.probe_all([good, missing])
    end
  end

  describe "track_attrs/1 and total_duration/1" do
    test "lay a multi-file recording end to end on one timeline" do
      files = for type <- [:mp3, :mp3, :mp3], do: fixture_file(type)
      {:ok, probes} = Scanner.probe_all(files)

      tracks = Scanner.track_attrs(probes)

      assert [%{index: 0}, %{index: 1}, %{index: 2}] = tracks

      # Each track starts where the previous one ended, with no gap and no
      # overlap, and the book is as long as all of them together.
      Enum.reduce(tracks, Decimal.new(0), fn track, expected_offset ->
        assert Decimal.equal?(track.start_offset, expected_offset)
        Decimal.add(expected_offset, track.duration)
      end)

      assert Decimal.equal?(
               Scanner.total_duration(probes),
               Enum.reduce(tracks, Decimal.new(0), &Decimal.add(&2, &1.duration))
             )
    end
  end

  describe "chapters/1" do
    test "takes the markers embedded in the files" do
      {:ok, probes} = Scanner.probe_all([chaptered_file()])

      assert {[first, second], :embedded} = Scanner.chapters(probes)
      assert first.title == "Opening Credits"
      assert Decimal.equal?(first.time, 0)
      assert second.title == "Chapter One"
      assert Decimal.compare(second.time, 0) == :gt
    end

    test "offers nothing when the files carry nothing" do
      {:ok, probes} = Scanner.probe_all([fixture_file(:m4a)])

      assert {[], _source} = Scanner.chapters(probes)
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

    test "reads them off the tracks when the recording was imported" do
      media = imported_media(tagged_media())

      assert {:ok, tags} = Scanner.tags(media)
      assert tags.book_title == "The Way of Kings"
    end

    test "reports a media with nothing to read" do
      media = insert(:media, book: build(:book))

      assert {:error, :no_audio_files} = Scanner.tags(media)
    end
  end

  # The same files, recorded the way an import records them: tracks, and no
  # transcode bookkeeping — nothing transcoded it. What the edit form's tag
  # evidence has to read for every recording the inbox has ever imported.
  defp imported_media(media) do
    Enum.each(Enum.with_index(media.source_files), fn {path, index} ->
      insert(:media_track, media: media, path: path, index: index)
    end)

    {:ok, media} =
      media.id
      |> Media.get_media!()
      |> Media.update_media(%{source_path: nil, source_files: []})

    Media.get_media!(media.id)
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

  # A real audio file on disk and nothing else. The probes take paths, not
  # recordings — that is the point of them — so these tests need no rows.
  defp fixture_file(type) do
    dir = Ambry.Paths.source_media_disk_path("probe-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)

    fixture = valid_audio(type)
    dest = Path.join(dir, "sample#{Path.extname(fixture)}")
    File.cp!(fixture, dest)

    dest
  end

  # ffmpeg is the only thing around that writes chapter atoms, so the fixture
  # is built the same way a real m4b gets them.
  defp chaptered_file do
    source_file = fixture_file(:m4a)

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

    chaptered_path
  end
end
