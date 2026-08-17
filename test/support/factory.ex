defmodule Ambry.Factory do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]
  use ExMachina.Ecto, repo: Ambry.Repo

  alias Ambry.Accounts.User
  alias Ambry.Books.Book
  alias Ambry.Books.BookUniverse
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesBook
  alias Ambry.Books.Universe
  alias Ambry.Fake
  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ambry.Media.Media
  alias Ambry.Media.MediaNarrator
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.RecordingGroup
  alias Ambry.People.Author
  alias Ambry.People.AuthorPerson
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Playback.Device
  alias Ambry.Playback.DeviceUser
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Search.Index

  # Users

  def user_factory do
    %User{
      email: Fake.email(),
      hashed_password: "fake"
    }
  end

  def admin_factory do
    build(:user, admin: true)
  end

  def confirmed_user_factory do
    build(:user, confirmed_at: NaiveDateTime.utc_now())
  end

  def valid_password, do: "HelloP@ssw0rd!"
  def valid_new_password, do: "NewP@ssw0rd!"

  def with_password(user, password \\ valid_password()) do
    user
    |> User.password_changeset(%{password: password})
    |> Ecto.Changeset.apply_action!(:insert)
  end

  # People

  # `authors` is a through association; the factory translates it into
  # `author_people` join rows so call sites can keep the natural shape.
  def person_factory(attrs) do
    {authors, attrs} = Map.pop(attrs, :authors)

    author_people =
      case authors do
        nil -> []
        authors -> Enum.map(authors, &%AuthorPerson{author: &1})
      end

    %Person{
      name: Fake.full_name(),
      description: Fake.paragraph(),
      author_people: author_people,
      narrators: []
    }
    |> merge_attributes(attrs)
    |> evaluate_lazy_attributes()
  end

  # `people` is a through association; the factory translates `person`/`people`
  # into `author_people` join rows so call sites can keep the natural shape.
  def author_factory(attrs) do
    {person, attrs} = Map.pop(attrs, :person)
    {people, attrs} = Map.pop(attrs, :people)

    author_people =
      case people || List.wrap(person) do
        [] -> []
        people -> Enum.map(people, &%AuthorPerson{person: &1})
      end

    %Author{
      name: Fake.full_name(),
      author_people: author_people
    }
    |> merge_attributes(attrs)
    |> evaluate_lazy_attributes()
  end

  def narrator_factory do
    %Narrator{
      name: Fake.full_name(),
      person: nil
    }
  end

  # Books

  def book_factory do
    %Book{
      title: book_title(),
      published: Fake.date_backward(15_466),
      published_format: Enum.random([:full, :year_month, :year]),
      book_authors: [],
      series_books: []
    }
  end

  defp book_title do
    prefix = sequence(:book_title_prefix, [nil, "Official", "Unauthorized", "Unofficial"])
    type = sequence(:book_title_type, ["Biography", "Autobiography", "Memoir"])
    name = Fake.full_name()

    ["The", prefix, type, "of", name] |> Enum.filter(& &1) |> Enum.join(" ")
  end

  def book_author_factory do
    %BookAuthor{
      author: nil,
      book: nil
    }
  end

  # Series

  def series_factory do
    %Series{
      name: series_name(),
      series_books: []
    }
  end

  defp series_name do
    name = Fake.last_name()

    suffix =
      sequence(:series_name_suffix, [
        "Chronicles",
        "Cycle",
        "Duology",
        "Novels",
        "Realm",
        "Series",
        "Story",
        "Trilogy"
      ])

    Enum.join(["The", name, suffix], " ")
  end

  # Universes

  def universe_factory do
    %Universe{
      name: "The #{Fake.last_name()} Universe",
      book_universes: []
    }
  end

  def book_universe_factory do
    %BookUniverse{
      book: nil,
      universe: nil
    }
  end

  def series_book_factory do
    %SeriesBook{book_number: Fake.integer(1, 10)}
  end

  # Media

  def media_factory do
    %Media{
      full_cast: Enum.random([true, false]),
      status: :pending,
      abridged: Enum.random([true, false]),
      published: Fake.date_backward(15_466),
      notes: Fake.sentence(),
      description: Fake.paragraph(),
      source_path: fn -> valid_source_path() end
    }
  end

  def recording_group_factory do
    %RecordingGroup{
      name: sequence(:recording_group_name, &"Recording Group #{&1}"),
      # tests pairing a group with media must pass the members' book here
      book: fn -> build(:book) end
    }
  end

  def media_track_factory do
    %MediaTrack{
      index: 0,
      path: fn -> "/uploads/source_media/#{Ecto.UUID.generate()}.m4b" end,
      size: trunc(Fake.uniform() * 500_000_000),
      mime: "audio/mp4",
      format: "mov,mp4,m4a,3gp,3g2,mj2",
      codec: "aac",
      duration: (Fake.uniform() * 30_000) |> Decimal.from_float() |> Decimal.round(2),
      start_offset: Decimal.new(0),
      seek_accuracy: :exact
    }
  end

  @doc """
  Gives a media a direct-play track per the given durations, laid end-to-end
  on the book's timeline.
  """
  def with_tracks(%Media{} = media, durations \\ ["3600.0"]) do
    {tracks, _offset} =
      durations
      |> Enum.with_index()
      |> Enum.map_reduce(Decimal.new(0), fn {duration, index}, offset ->
        duration = Decimal.new(duration)

        track =
          build(:media_track, index: index, duration: duration, start_offset: offset)

        {track, Decimal.add(offset, duration)}
      end)

    %{media | media_tracks: tracks}
  end

  @doc """
  Gives a persisted media the tracks an import would write for real audio.

  Real files, really probed: what a test wants when it cares about codecs,
  sizes, seek accuracy or a duration that has to add up. The scanner that
  once did this in one call is gone — importing is how a recording gets
  tracks — so this does what the importer does with the probes it takes.

  The recording comes out in an import's shape: tracks, and neither of the
  transcode columns.
  """
  def with_probed_tracks(%Media{__meta__: %{state: :loaded}} = media, type \\ :m4a, count \\ 1) do
    media = media.id |> Ambry.Media.get_media!() |> with_copied_source_files(type, count)
    paths = Enum.map(media.source_files, &Ambry.Paths.web_to_disk/1)

    {:ok, probes} = Ambry.Media.Scanner.probe_all(paths)

    tracks =
      probes
      |> Ambry.Media.Scanner.track_attrs()
      |> Enum.map(&%{&1 | path: Ambry.Paths.disk_to_web(&1.path)})

    {:ok, media} =
      Ambry.Media.update_media(media, %{
        media_tracks: tracks,
        duration: Ambry.Media.Scanner.total_duration(probes),
        source_path: nil,
        source_files: []
      })

    Ambry.Media.get_media!(media.id)
  end

  # The fixture is copied into the media's own workspace so the stored path
  # has a resolvable `/uploads/...` form — absolute paths outside the
  # uploads tree can no longer be stored. A copy, not a hardlink: the
  # checkout and the uploads tree may sit on different filesystems.
  def with_source_files(%Media{} = media, type \\ :m4a, count \\ 1) do
    fixture = valid_audio(type)
    folder = Media.source_path(media)
    File.mkdir_p!(folder)

    files =
      for index <- 1..count do
        dest = Path.join(folder, "#{index}-source#{Path.extname(fixture)}")
        if not File.exists?(dest), do: File.cp!(fixture, dest)
        Ambry.Paths.disk_to_web(dest)
      end

    %{media | source_files: files}
  end

  @doc """
  Copies real audio fixtures into the media's own source folder, the way an
  upload does — so `source_files` holds absolute paths to files that are
  actually there and can be probed.
  """
  def with_copied_source_files(%Media{} = media, type \\ :m4a, count \\ 1) do
    fixture = valid_audio(type)
    folder = Media.source_path(media)
    File.mkdir_p!(folder)

    files =
      for index <- 1..count do
        dest = Path.join(folder, "#{index}-sample#{Path.extname(fixture)}")
        File.cp!(fixture, dest)
        Ambry.Paths.disk_to_web(dest)
      end

    %{media | source_files: files}
  end

  @doc """
  Gives a media the packaged artifacts a transcode used to leave behind.

  Ambry does not transcode any more — the pipeline retired with the last
  upload form — but the library is full of recordings that were transcoded
  before that, and serving them is still the server's job. So this writes
  the four files shaka-packager produced, under the names it produced them
  with, instead of producing them: same columns, same disk layout, no
  ffmpeg and no packager.

  The bytes are placeholders. Nothing left in the codebase reads inside a
  packaged artifact — they are served as opaque files and deleted as opaque
  files — so a test that needs one needs its name, its size and its
  existence.
  """
  def with_output_files(%Media{__meta__: %{state: :loaded}} = media) do
    id = Ecto.UUID.generate()
    File.mkdir_p!(Ambry.Paths.media_disk_path())

    for name <- ["#{id}.mp4", "#{id}.mpd", "#{id}.m3u8", "#{id}_0.m3u8"] do
      File.write!(Ambry.Paths.media_disk_path(name), "packaged: #{name}\n")
    end

    {:ok, media} =
      Ambry.Media.update_media(media, %{
        mp4_path: "/uploads/media/#{id}.mp4",
        mpd_path: "/uploads/media/#{id}.mpd",
        hls_path: "/uploads/media/#{id}.m3u8",
        duration: Decimal.new("3600.0"),
        status: :ready
      })

    media
  end

  def with_output_files(_media),
    do: raise("Giving a media output files requires database persisted media")

  def media_narrator_factory do
    %MediaNarrator{
      narrator: nil,
      media: nil
    }
  end

  def chapter_factory do
    %Media.Chapter{}
  end

  # Playback

  def device_factory do
    %Device{
      id: Ecto.UUID.generate(),
      type: Enum.random([:ios, :android, :web]),
      brand: Fake.company_name(),
      model_name: sequence(:model_name, &"Model-#{&1}"),
      os_name: Enum.random(["iOS", "Android", "Windows", "macOS", "Linux"]),
      os_version: "#{Fake.integer(10, 16)}.0"
    }
  end

  def device_user_factory do
    %DeviceUser{
      device: build(:device),
      user: build(:user),
      last_seen_at: DateTime.utc_now()
    }
  end

  def playthrough_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    %Playthrough{
      id: Ecto.UUID.generate(),
      user: build(:user),
      media: build(:media, book: build(:book)),
      status: :in_progress,
      started_at: now,
      last_event_at: now,
      position: Decimal.new(0),
      rate: Decimal.new("1.0"),
      refreshed_at: DateTime.utc_now()
    }
  end

  def playback_event_factory do
    %PlaybackEvent{
      id: Ecto.UUID.generate(),
      playthrough_id: Ecto.UUID.generate(),
      type: :play,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
      position: Decimal.new("#{Fake.integer(0, 1000)}.0"),
      playback_rate: Decimal.new("1.0")
    }
  end

  def lifecycle_event_factory do
    build(:playback_event,
      type: :start,
      position: nil,
      playback_rate: nil
    )
  end

  # Search indexes

  def with_search_index(%_{__meta__: %{state: :built}}),
    do: raise("Inserting search indexes requires database persisted records")

  def with_search_index(%Person{id: id} = person) do
    Index.insert!(:person, id)
    person
  end

  def with_search_index(%Book{id: id} = book) do
    Index.insert!(:book, id)
    book
  end

  def with_search_index(%Series{id: id} = series) do
    Index.insert!(:series, id)
    series
  end

  def with_search_index(%Media{id: id} = media) do
    Index.insert!(:media, id)
    media
  end

  # Images and Thumbnails

  def with_image(%Person{} = person) do
    %{person | image_path: valid_image(:person)[:web_path]}
  end

  def with_image(%Media{} = media) do
    %{media | image_path: valid_image(:media)[:web_path]}
  end

  def with_thumbnails(%Person{} = person) do
    %{web_path: image_web_path} = valid_image(:person)

    thumbnails_attrs = Ambry.Thumbnails.generate_thumbnails!(image_web_path)

    thumbnails =
      %Ambry.Thumbnails{}
      |> Ambry.Thumbnails.changeset(thumbnails_attrs)
      |> Ecto.Changeset.apply_action!(:insert)

    %{person | image_path: image_web_path, thumbnails: thumbnails}
  end

  def with_thumbnails(%Media{} = media) do
    %{web_path: image_web_path} = valid_image(:media)

    thumbnails_attrs = Ambry.Thumbnails.generate_thumbnails!(image_web_path)

    thumbnails =
      %Ambry.Thumbnails{}
      |> Ambry.Thumbnails.changeset(thumbnails_attrs)
      |> Ecto.Changeset.apply_action!(:insert)

    %{media | image_path: image_web_path, thumbnails: thumbnails}
  end

  # Test files

  # Stored form: paths in the database are `/uploads/...` (or
  # root-relative), never absolute. The folder still exists on disk.
  def valid_source_path do
    path = Ambry.Paths.source_media_disk_path(Ecto.UUID.generate())
    File.mkdir_p!(path)
    Ambry.Paths.disk_to_web(path)
  end

  # Library sources and roots

  def source_factory do
    %Source{
      name: sequence(:source_name, &"Source #{&1}"),
      path: sequence(:source_path, &"/data/source-#{&1}"),
      enabled: true
    }
  end

  def root_factory do
    %Root{
      name: sequence(:root_name, &"Root #{&1}"),
      path: sequence(:root_path, &"/data/root-#{&1}")
    }
  end

  def valid_image(:person), do: copy_test_image("test/support/files/jules_verne.jpg")
  def valid_image(:media), do: copy_test_image("test/support/files/mysterious_island.jpg")

  defp copy_test_image(test_file_path) do
    id = Ecto.UUID.generate()
    filename = "#{id}.jpg"
    disk_path = Ambry.Paths.images_disk_path(filename)
    web_path = "/uploads/images/#{filename}"
    File.cp!(test_file_path, disk_path)

    %{
      web_path: web_path,
      disk_path: Ambry.Paths.web_to_disk(web_path)
    }
  end

  @doc """
  A real m4b carrying real embedded tags, since the inbox reads them.

  Written into its own folder under `source_media` because the file-audit
  tests list that directory and expect only folders.
  """
  def tagged_audio(opts \\ []) do
    if Keyword.get(opts, :cover_art, false),
      do: tagged_mp3_with_art(opts),
      else: tagged_m4b(opts)
  end

  defp tagged_m4b(opts) do
    path = fixture_path("tagged.m4b")

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        ["-v", "quiet", "-i", valid_audio(:m4a), "-c", "copy"] ++
          metadata_args(opts) ++ [path]
      )

    path
  end

  # Cover art rides along as an attached_pic video stream. ffmpeg's mov muxer
  # is fussy about writing one, so an art-bearing fixture is an mp3 — which
  # the probe and the extractor treat identically.
  defp tagged_mp3_with_art(opts) do
    path = fixture_path("tagged-art.mp3")
    art = Path.rootname(path) <> ".jpg"

    {_output, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "quiet",
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=c=red:s=64x64:d=1",
        "-frames:v",
        "1",
        art
      ])

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-v",
          "quiet",
          "-y",
          "-i",
          valid_audio(:mp3),
          "-i",
          art,
          "-map",
          "0:a",
          "-map",
          "1:v",
          "-c",
          "copy",
          "-id3v2_version",
          "3"
        ] ++ metadata_args(opts) ++ [path]
      )

    File.rm(art)
    path
  end

  defp metadata_args(opts) do
    [
      "-metadata",
      "album=#{Keyword.get(opts, :album, "The Way of Kings")}",
      "-metadata",
      "artist=#{Keyword.get(opts, :artist, "Brandon Sanderson")}",
      "-metadata",
      "composer=#{Keyword.get(opts, :composer, "Michael Kramer, Kate Reading")}"
    ] ++
      if Keyword.get(opts, :dated, true), do: ["-metadata", "date=2010-08-31"], else: []
  end

  defp fixture_path(filename) do
    dir = Ambry.Paths.source_media_disk_path("fixture-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)
    Path.join(dir, filename)
  end

  def valid_audio(:flac), do: "test/support/files/sample.flac"
  def valid_audio(:m4a), do: "test/support/files/sample.m4a"
  def valid_audio(:mp3), do: "test/support/files/sample.mp3"
  def valid_audio(:ogg), do: "test/support/files/sample.ogg"
  def valid_audio(:opus), do: "test/support/files/sample.opus"
  def valid_audio(:wav), do: "test/support/files/sample.wav"
end
