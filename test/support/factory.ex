defmodule Ambry.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Ambry.Repo

  alias Ambry.Accounts.User
  alias Ambry.Authors.{Author, BookAuthor}
  alias Ambry.Books.Book
  alias Ambry.Media.{Media, MediaNarrator, PlayerState}
  alias Ambry.Narrators.Narrator
  alias Ambry.People.Person
  alias Ambry.Series.{Series, SeriesBook}

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
    image_path = "/uploads/images/" <> Faker.File.file_name(:image)

    disk_path = Ambry.Paths.web_to_disk(image_path)
    File.touch!(disk_path)

    %Person{
      name: Faker.Person.name(),
      description: Faker.Lorem.paragraph(),
      image_path: image_path
    }
  end

  def author_factory do
    name = Faker.Person.name()

    %Author{
      name: name,
      person: build(:person, name: name)
    }
  end

  def narrator_factory do
    name = Faker.Person.name()

    %Narrator{
      name: name,
      person: build(:person, name: name)
    }
  end

  def media_narrator_factory do
    %MediaNarrator{
      narrator: build(:narrator)
    }
  end

  def book_author_factory do
    %BookAuthor{
      author: build(:author)
    }
  end

  # Books

  def book_factory do
    image_path = "/uploads/images/" <> Faker.File.file_name(:image)

    disk_path = Ambry.Paths.web_to_disk(image_path)
    File.touch!(disk_path)

    %Book{
      title: book_title(),
      published: Faker.Date.backward(15_466),
      description: Faker.Lorem.paragraph(),
      image_path: image_path,
      book_authors: build_list(Faker.random_between(1, 2), :book_author),
      series_books: build_list(Faker.random_between(1, 2), :series_book)
    }
  end

  defp book_title do
    prefix = sequence(:book_title_prefix, [nil, "Official", "Unauthorized", "Unofficial"])
    type = sequence(:book_title_type, ["Biography", "Autobiography", "Memoir"])
    name = Faker.Person.name()

    ["The", prefix, type, "of", name] |> Enum.filter(& &1) |> Enum.join(" ")
  end

  # Series

  def series_factory do
    %Series{
      name: series_name()
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

    ["The", name, suffix] |> Enum.join(" ")
  end

  def series_book_factory do
    %SeriesBook{
      series: build(:series),
      book_number: Faker.random_between(1, 10)
    }
  end

  # Media

  def media_factory do
    ExMachina.Sequence.reset([:chapter_time, :chapter_number])

    chapters = build_list(Faker.random_between(10, 40), :chapter)
    %{time: time} = List.last(chapters)
    duration = Decimal.new(time + 300)

    media_id = Ecto.UUID.generate()

    %Media{
      book: build(:book),
      media_narrators: build_list(Faker.random_between(1, 2), :media_narrator),
      chapters: chapters,
      full_cast: Enum.random([true, false]),
      status: Enum.random(Media.statuses()),
      abridged: Enum.random([true, false]),
      source_path: "/source_media/#{Ecto.UUID.generate()}",
      mpd_path: "/media/#{media_id}.mpd",
      hls_path: "/media/#{media_id}.m3u8",
      mp4_path: "/media/#{media_id}.mp4",
      duration: duration
    }
  end

  def chapter_factory do
    %Media.Chapter{
      time: sequence(:chapter_time, &(&1 * 300)),
      title: sequence(:chapter_number, &"Chapter #{&1 + 1}")
    }
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
end
