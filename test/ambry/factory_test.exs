# Examples of how to use the factories correctly to create the data you want.

defmodule Ambry.FactoryTest do
  use Ambry.DataCase

  import Ambry.Paths

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Books.SeriesBook
  alias Ambry.Media.Media
  alias Ambry.Media.Media.Chapter
  alias Ambry.Media.MediaNarrator
  alias Ambry.People.Author
  alias Ambry.People.BookAuthor
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Thumbnails

  describe "People" do
    test "creates a person with a random name and description, but no image or thumbnails" do
      person = insert(:person)

      assert %Person{} = person
      assert is_binary(person.name)
      assert is_binary(person.description)
      refute person.image_path
      refute person.thumbnails
      assert person.authors == []
      assert person.narrators == []
    end

    test "creates a person with a valid image" do
      person = :person |> build() |> with_image() |> insert()

      assert %Person{} = person
      assert is_binary(person.image_path)
      assert person.image_path |> web_to_disk() |> File.exists?()
    end

    test "creates a person with a valid image and generated thumbnails of that image" do
      person = :person |> build() |> with_thumbnails() |> insert()

      assert %Person{} = person
      assert is_binary(person.image_path)
      assert person.image_path |> web_to_disk() |> File.exists?()
      assert %Thumbnails{} = person.thumbnails
      assert person.thumbnails.extra_small |> web_to_disk() |> File.exists?()
      assert person.thumbnails.small |> web_to_disk() |> File.exists?()
      assert person.thumbnails.medium |> web_to_disk() |> File.exists?()
      assert person.thumbnails.large |> web_to_disk() |> File.exists?()
      assert person.thumbnails.extra_large |> web_to_disk() |> File.exists?()
    end

    test "creates a person that writes as an author under an alias" do
      person =
        insert(:person, name: "Real Name", authors: build_list(1, :author, name: "Pen Name"))

      assert %Person{} = person
      assert "Real Name" = person.name
      assert [%Author{name: "Pen Name"}] = person.authors
    end

    test "creates a person that narrates as a narrator under an alias" do
      person =
        insert(:person,
          name: "Real Name",
          narrators: build_list(1, :narrator, name: "Narrator Name")
        )

      assert %Person{} = person
      assert "Real Name" = person.name
      assert [%Narrator{name: "Narrator Name"}] = person.narrators
    end

    test "creates a person that writes under multiple pen names, but also under their own name" do
      person =
        insert(:person,
          name: "Real Name",
          authors: [build(:author, name: "Real Name") | build_list(2, :author)]
        )

      assert %Person{} = person
      assert "Real Name" = person.name
      assert 3 = length(person.authors)
    end
  end

  describe "Books" do
    test "creates a book with a random title, published date, and date format" do
      book = insert(:book)

      assert %Book{} = book
      assert is_binary(book.title)
      assert %Date{} = book.published
      assert book.published_format in [:full, :year_month, :year]
      assert book.series_books == []
      assert book.book_authors == []
    end

    test "creates a book with an author" do
      book =
        insert(:book,
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )

      assert %Book{} = book
      assert [%BookAuthor{author: author}] = book.book_authors
      assert %Author{} = author
      assert %Person{} = author.person
    end

    test "creates a book with multiple authors" do
      book =
        insert(:book,
          book_authors:
            build_list(2, :book_author, author: build(:author, person: build(:person)))
        )

      assert %Book{} = book
      assert 2 = length(book.book_authors)
      assert [%BookAuthor{author: author1}, %BookAuthor{author: author2}] = book.book_authors
      assert %Author{} = author1
      assert %Person{} = author1.person
      assert %Author{} = author2
      assert %Person{} = author2.person
    end

    test "creates a book that's part of a series" do
      book =
        insert(:book,
          series_books: [build(:series_book, book_number: 1, series: build(:series))]
        )

      assert %Book{} = book
      assert [%SeriesBook{series: series}] = book.series_books
      assert %Series{} = series
    end
  end

  describe "Series" do
    test "creates a series with a random name" do
      series = insert(:series)

      assert %Series{} = series
      assert is_binary(series.name)
      assert series.series_books == []
    end

    test "creates a series with a book" do
      series =
        insert(:series,
          series_books: [build(:series_book, book_number: 1, book: build(:book))]
        )

      assert %Series{} = series
      assert [%SeriesBook{book: book}] = series.series_books
      assert %Book{} = book
    end

    test "creates a series with multiple books" do
      series =
        insert(:series,
          series_books: [
            build(:series_book, book_number: 1, book: build(:book)),
            build(:series_book, book_number: 2, book: build(:book))
          ]
        )

      assert %Series{} = series
      assert 2 = length(series.series_books)
      assert [%SeriesBook{book: book1}, %SeriesBook{book: book2}] = series.series_books
      assert %Book{} = book1
      assert %Book{} = book2
    end
  end

  describe "Media" do
    test "creates pending media for a given book" do
      media = insert(:media, book: build(:book))

      assert %Media{} = media
      assert :pending = media.status
      assert %Book{} = media.book
    end

    test "creates pending media for a given book with a narrator" do
      media =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      assert %Media{} = media
      assert :pending = media.status
      assert %Book{} = media.book
      assert [%MediaNarrator{narrator: narrator}] = media.media_narrators
      assert %Narrator{} = narrator
    end

    test "creates pending media for a given book with multiple narrators" do
      media =
        insert(:media,
          book: build(:book),
          media_narrators:
            build_list(2, :media_narrator, narrator: build(:narrator, person: build(:person)))
        )

      assert %Media{} = media
      assert :pending = media.status
      assert %Book{} = media.book
      assert 2 = length(media.media_narrators)

      assert [%MediaNarrator{narrator: narrator1}, %MediaNarrator{narrator: narrator2}] =
               media.media_narrators

      assert %Narrator{} = narrator1
      assert %Narrator{} = narrator2
    end

    test "creates media with a valid image" do
      media = :media |> build(book: build(:book)) |> with_image() |> insert()

      assert %Media{} = media
      assert is_binary(media.image_path)
      assert media.image_path |> web_to_disk() |> File.exists?()
    end

    test "creates media with a valid image and generated thumbnails of that image" do
      media = :media |> build(book: build(:book)) |> with_thumbnails() |> insert()

      assert %Media{} = media
      assert is_binary(media.image_path)
      assert media.image_path |> web_to_disk() |> File.exists?()
      assert %Thumbnails{} = media.thumbnails
      assert media.thumbnails.extra_small |> web_to_disk() |> File.exists?()
      assert media.thumbnails.small |> web_to_disk() |> File.exists?()
      assert media.thumbnails.medium |> web_to_disk() |> File.exists?()
      assert media.thumbnails.large |> web_to_disk() |> File.exists?()
      assert media.thumbnails.extra_large |> web_to_disk() |> File.exists?()
    end

    test "creates media with valid source files" do
      media =
        :media |> build(book: build(:book)) |> with_source_files() |> insert()

      assert %Media{} = media
      assert is_binary(media.source_path)

      for path <- media.source_files do
        assert is_binary(path)
        assert File.exists?(path)
      end
    end

    test "creates media with valid output files" do
      media =
        :media
        |> build(book: build(:book))
        |> with_source_files()
        |> insert()
        |> with_output_files()

      assert %Media{} = media
      assert media.status == :ready
      assert media.mp4_path |> web_to_disk() |> File.exists?()
      assert media.hls_path |> web_to_disk() |> File.exists?()
      assert media.mpd_path |> web_to_disk() |> File.exists?()
      assert media.hls_path |> hls_playlist_path() |> web_to_disk() |> File.exists?()
      assert %Decimal{} = media.duration
    end

    test "creates media with chapters" do
      media =
        :media
        |> build(book: build(:book), chapters: [build(:chapter, time: 0, title: "Chapter 1")])
        |> insert()

      assert %Media{} = media
      assert [%Chapter{} = chapter] = media.chapters
      assert chapter.time == Decimal.new(0)
      assert chapter.title == "Chapter 1"
    end
  end
end
