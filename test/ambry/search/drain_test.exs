defmodule Ambry.Search.DrainTest do
  @moduledoc """
  The index is asserted the way it is now maintained: nothing here indexes
  anything by hand. Every test writes through a context — or, in one case,
  straight through `Repo` the way `Ambry.Inbox.Importer` does — and then drains.

  The predecessor of this file called `Index.insert!/2` itself and asserted on
  a `dependencies` column, which meant it could only ever prove that indexing
  works when you remember to index. That was the bug.
  """

  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.People.AuthorPerson
  alias Ambry.Repo
  alias Ambry.Search.Drain
  alias Ambry.Search.Record
  alias Ambry.Search.Reference

  describe "books" do
    test "a new book is indexed without anyone asking" do
      %{title: title} = book = insert(:book)

      drain()

      assert %{primary: ^title} = fetch_record(book)
    end

    test "a book's record picks up its recordings' narrators" do
      book = insert(:book)
      drain()

      refute fetch_record(book).secondary

      %{media_narrators: [%{narrator: narrator}]} =
        insert(:media,
          book: book,
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      drain()

      assert fetch_record(book).secondary =~ narrator.name
    end

    test "renaming a book rewrites its record" do
      book = insert(:book)
      drain()

      {:ok, _book} = Books.update_book(book, %{title: "New Book Title"})
      drain()

      assert %{primary: "New Book Title"} = fetch_record(book)
    end

    test "deleting a book removes its record" do
      book = insert(:book)
      drain()

      assert fetch_record(book)

      {:ok, _book} = Books.delete_book(book)
      drain()

      assert nil == fetch_record(book)
    end

    test "moving a recording to another book rewrites both" do
      %{book: book_one, media_narrators: [%{narrator: narrator}]} =
        media =
        insert(:media,
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )

      book_two = insert(:book)
      drain()

      assert fetch_record(book_one).secondary =~ narrator.name
      refute fetch_record(book_two).secondary

      {:ok, _media} = Media.update_media(media, %{book_id: book_two.id})
      drain()

      # The row that knew about the old book is the one that was overwritten,
      # which is why the trigger enqueues from OLD as well as NEW.
      refute fetch_record(book_one).secondary
      assert fetch_record(book_two).secondary =~ narrator.name
    end
  end

  describe "series" do
    test "adding books to a series rewrites the series and its books" do
      [book_one, book_two] = insert_pair(:book, series_books: [])
      drain()

      refute fetch_record(book_one).secondary

      %{name: series_name} =
        series =
        insert(:series,
          series_books: [
            %{book_id: book_one.id, book_number: 1},
            %{book_id: book_two.id, book_number: 2}
          ]
        )

      drain()

      assert %{primary: ^series_name} = fetch_record(series)
      assert fetch_record(book_one).secondary =~ series_name
      assert fetch_record(book_two).secondary =~ series_name
    end

    test "a series with no books is not indexed" do
      series = insert(:series, series_books: [])

      drain()

      assert nil == fetch_record(series)
    end

    test "emptying a series removes its record" do
      [book_one, book_two] = insert_pair(:book, series_books: [])

      %{series_books: [%{id: series_book_id_one}, %{id: series_book_id_two}]} =
        series =
        insert(:series,
          series_books: [
            %{book_id: book_one.id, book_number: 1},
            %{book_id: book_two.id, book_number: 2}
          ]
        )

      drain()

      assert fetch_record(series)

      {:ok, _series} =
        Books.update_series(series, %{
          series_books_drop: [0, 1],
          series_books: %{
            0 => %{id: series_book_id_one},
            1 => %{id: series_book_id_two}
          }
        })

      drain()

      assert nil == fetch_record(series)
    end
  end

  describe "people" do
    test "a new person is indexed" do
      %{name: name} = person = insert(:person)

      drain()

      assert %{primary: ^name} = fetch_record(person)
    end

    test "renaming a person rewrites every record that quotes them" do
      %{author_people: [%{id: author_person_id, author: author}], narrators: [narrator]} =
        person =
        insert(:person,
          authors: build_list(1, :author),
          narrators: build_list(1, :narrator)
        )

      authored = insert(:book, book_authors: [%{author_id: author.id}])

      %{book: narrated} =
        insert(:media, book: build(:book), media_narrators: [%{narrator_id: narrator.id}])

      drain()

      assert %{primary: primary, secondary: secondary} = fetch_record(person)
      assert primary =~ author.name
      assert primary =~ narrator.name
      assert secondary == person.name

      assert fetch_record(authored).secondary =~ author.name
      assert fetch_record(authored).tertiary =~ person.name
      assert fetch_record(narrated).secondary =~ narrator.name
      assert fetch_record(narrated).tertiary =~ person.name

      {:ok, _person} =
        People.update_person(person, %{
          name: "PersonName",
          author_people: [%{id: author_person_id, author: %{id: author.id, name: "AuthorName"}}],
          narrators: [%{id: narrator.id, name: "NarratorName"}]
        })

      drain()

      assert %{primary: primary, secondary: "PersonName"} = fetch_record(person)
      assert primary =~ "AuthorName"
      assert primary =~ "NarratorName"

      assert %{secondary: secondary, tertiary: tertiary} = fetch_record(authored)
      assert secondary =~ "AuthorName"
      assert tertiary =~ "PersonName"
      refute secondary =~ author.name

      assert %{secondary: secondary, tertiary: tertiary} = fetch_record(narrated)
      assert secondary =~ "NarratorName"
      assert tertiary =~ "PersonName"
      refute secondary =~ narrator.name
    end

    test "a write that never touches Ambry.Search still reaches the index" do
      person = insert(:person)
      author = insert(:author)
      book = insert(:book, book_authors: [%{author_id: author.id}])
      drain()

      refute fetch_record(person).primary =~ author.name

      # What `Ambry.Inbox.Importer` does when a :create author credit lands
      # against an existing person: a bare join row, from a boundary that is
      # not allowed to call `Ambry.Search` at all.
      Repo.insert!(%AuthorPerson{author_id: author.id, person_id: person.id})
      drain()

      assert fetch_record(person).primary =~ author.name
      assert fetch_record(book).tertiary =~ person.name
    end
  end

  defp drain do
    assert {:ok, _count} = Drain.run()
  end

  defp fetch_record(struct) do
    reference = Reference.new(struct)

    Repo.one(
      from record in Record,
        where: record.reference == type(^reference, Reference.Type)
    )
  end
end
