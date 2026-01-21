defmodule Ambry.Factory do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]
  use ExMachina.Ecto, repo: Ambry.Repo

  alias Ambry.Accounts.User
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesBook
  alias Ambry.Media.Bookmark
  alias Ambry.Media.Media
  alias Ambry.Media.MediaNarrator
  alias Ambry.Media.PlayerState
  alias Ambry.People.Author
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Playback.Device
  alias Ambry.Playback.PlaybackEvent
  alias Ambry.Playback.Playthrough
  alias Ambry.Playback.PlaythroughNew
  alias Ambry.Search.Index

  # Users

  def user_factory do
    %User{
      email: Faker.Internet.email(),
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

  def person_factory do
    %Person{
      name: Faker.Person.name(),
      description: Faker.Lorem.paragraph(),
      authors: [],
      narrators: []
    }
  end

  def author_factory do
    %Author{
      name: Faker.Person.name(),
      person: nil
    }
  end

  def narrator_factory do
    %Narrator{
      name: Faker.Person.name(),
      person: nil
    }
  end

  # Books

  def book_factory do
    %Book{
      title: book_title(),
      published: Faker.Date.backward(15_466),
      published_format: Enum.random([:full, :year_month, :year]),
      book_authors: [],
      series_books: []
    }
  end

  defp book_title do
    prefix = sequence(:book_title_prefix, [nil, "Official", "Unauthorized", "Unofficial"])
    type = sequence(:book_title_type, ["Biography", "Autobiography", "Memoir"])
    name = Faker.Person.name()

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
    name = Faker.Person.last_name()

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

  def series_book_factory do
    %SeriesBook{book_number: Faker.random_between(1, 10)}
  end

  # Media

  def media_factory do
    %Media{
      full_cast: Enum.random([true, false]),
      status: :pending,
      abridged: Enum.random([true, false]),
      published: Faker.Date.backward(15_466),
      notes: Faker.Lorem.sentence(),
      description: Faker.Lorem.paragraph(),
      source_path: fn -> valid_source_path() end
    }
  end

  def with_source_files(%Media{} = media, type \\ :m4a, count \\ 1) do
    audio_file_disk_path = valid_audio(type)

    %{media | source_files: for(_ <- 1..count, do: audio_file_disk_path)}
  end

  def with_output_files(media, processor \\ :auto)

  def with_output_files(%Media{__meta__: %{state: :loaded}} = media, processor) do
    {:ok, media} = Ambry.Media.Processor.run!(media, processor)
    media
  end

  def with_output_files(_media, _processor),
    do: raise("Generating media output files requires database persisted media")

  def media_narrator_factory do
    %MediaNarrator{
      narrator: nil,
      media: nil
    }
  end

  def chapter_factory do
    %Media.Chapter{}
  end

  # Player States

  def player_state_factory do
    %PlayerState{
      media: build(:media),
      playback_rate: Enum.random(Enum.map(["1.0", "1.25", "1.5", "1.75", "2.0"], &Decimal.new/1)),
      position: Decimal.new(0),
      status: :not_started
    }
  end

  # Playback

  def device_factory do
    %Device{
      id: Ecto.UUID.generate(),
      user: build(:user),
      type: Enum.random([:ios, :android, :web]),
      brand: Faker.Company.name(),
      model_name: sequence(:model_name, &"Model-#{&1}"),
      os_name: Enum.random(["iOS", "Android", "Windows", "macOS", "Linux"]),
      os_version: "#{Faker.random_between(10, 16)}.0",
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }
  end

  def playthrough_factory do
    %Playthrough{
      id: Ecto.UUID.generate(),
      user: build(:user),
      media: build(:media, book: build(:book)),
      status: :in_progress,
      started_at: DateTime.utc_now() |> DateTime.truncate(:millisecond)
    }
  end

  def finished_playthrough_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    build(:playthrough,
      status: :finished,
      finished_at: now
    )
  end

  def abandoned_playthrough_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    build(:playthrough,
      status: :abandoned,
      abandoned_at: now
    )
  end

  def playthrough_new_factory do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    %PlaythroughNew{
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
      playthrough: build(:playthrough),
      type: :play,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
      position: Decimal.new("#{Faker.random_between(0, 1000)}.0"),
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

  # Bookmarks

  def bookmark_factory do
    %Bookmark{
      position: (Faker.random_uniform() * 1000) |> Decimal.from_float() |> Decimal.round(1),
      label: Faker.Lorem.word()
    }
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

  def valid_source_path do
    path = Ambry.Paths.source_media_disk_path(Ecto.UUID.generate())
    File.mkdir_p!(path)
    path
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

  def valid_audio(:flac), do: "test/support/files/sample.flac"
  def valid_audio(:m4a), do: "test/support/files/sample.m4a"
  def valid_audio(:mp3), do: "test/support/files/sample.mp3"
  def valid_audio(:ogg), do: "test/support/files/sample.ogg"
  def valid_audio(:opus), do: "test/support/files/sample.opus"
  def valid_audio(:wav), do: "test/support/files/sample.wav"
end
