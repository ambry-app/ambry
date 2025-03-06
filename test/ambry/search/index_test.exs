defmodule Ambry.Search.IndexTest do
  @moduledoc false

  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.Repo
  alias Ambry.Search.Index
  alias Ambry.Search.Record
  alias Ambry.Search.Reference

  describe "insert(:book, id)" do
    test "indexes a new book" do
      %{book: %{title: book_title} = book} = insert(:media)

      assert :ok = Index.insert!(:book, book.id)

      assert %{
               primary: ^book_title
             } = fetch_record(book)
    end
  end

  describe "insert(:media, id)" do
    test "updates the index of the associated book" do
      book = insert(:book)
      Index.insert!(:book, book.id)
      initial_book_record = fetch_record(book)

      media = insert(:media, book: book)
      narrator_references = Enum.map(media.media_narrators, &Reference.new(&1.narrator.person))

      # the narrators are not part of the initial book index record
      refute Enum.all?(narrator_references, fn ref ->
               ref in initial_book_record.dependencies
             end)

      assert :ok = Index.insert!(:media, media.id)
      updated_book_record = fetch_record(book)

      # now the narrators are part of the book index record
      assert Enum.all?(narrator_references, fn ref ->
               ref in updated_book_record.dependencies
             end)
    end
  end

  describe "insert(:person, id)" do
    test "indexes a new person" do
      %{name: person_name} = person = insert(:person)

      assert :ok = Index.insert!(:person, person.id)

      assert %{
               primary: ^person_name
             } = fetch_record(person)
    end
  end

  describe "insert(:series, id)" do
    test "indexes a new series and updates the index of all referenced books" do
      [book1, book2] = books = insert_pair(:book, series_books: [])
      Enum.each(books, &Index.insert!(:book, &1.id))
      initial_book_records = Enum.map(books, &fetch_record/1)

      # The books were indexed without any series
      assert Enum.all?(initial_book_records, fn record ->
               not Enum.any?(record.dependencies, &(&1.type == :series))
             end)

      series =
        insert(:series,
          series_books: [
            %{book_id: book1.id, book_number: 1},
            %{book_id: book2.id, book_number: 2}
          ]
        )

      series_ref = Reference.new(series)

      assert :ok = Index.insert!(:series, series.id)

      updated_book_records = Enum.map(books, &fetch_record/1)

      # The books now reference the series
      assert Enum.all?(updated_book_records, fn record ->
               series_ref in record.dependencies
             end)
    end

    test "does not index a new series if it has no books" do
      series = insert(:series, series_books: [])

      assert :ok = Index.insert!(:series, series.id)

      assert nil == fetch_record(series)
    end
  end

  describe "update(:book, id)" do
    test "updates the index of a book" do
      %{book: %{title: book_title} = book} = insert(:media)

      assert :ok = Index.insert!(:book, book.id)

      assert %{
               primary: ^book_title
             } = fetch_record(book)

      new_book_title = "New Book Title"
      {:ok, _book} = Books.update_book(book, %{title: new_book_title})

      assert :ok = Index.update!(:book, book.id)

      assert %{
               primary: ^new_book_title
             } = fetch_record(book)
    end
  end

  describe "update(:media, id)" do
    test "updates the index of all books involved in the operation" do
      %{book: book_one, media_narrators: [%{narrator: narrator} | _rest]} = media = insert(:media)
      book_two = insert(:book)
      Index.insert!(:book, book_one.id)
      Index.insert!(:book, book_two.id)

      narrator_ref = Reference.new(narrator.person)
      media_ref = Reference.new(media)

      book_one_record = fetch_record(book_one)
      book_two_record = fetch_record(book_two)

      assert media_ref in book_one_record.dependencies
      assert narrator_ref in book_one_record.dependencies

      refute media_ref in book_two_record.dependencies
      refute narrator_ref in book_two_record.dependencies

      {:ok, _book_two} = Media.update_media(media, %{book_id: book_two.id})
      assert :ok = Index.update!(:media, media.id)

      book_one_record = fetch_record(book_one)
      book_two_record = fetch_record(book_two)

      refute media_ref in book_one_record.dependencies
      refute narrator_ref in book_one_record.dependencies

      assert media_ref in book_two_record.dependencies
      assert narrator_ref in book_two_record.dependencies
    end
  end

  describe "update(:person, id)" do
    test "updates all index records that reference this person" do
      %{
        name: person_name,
        authors: [author],
        narrators: [narrator]
      } =
        person =
        insert(:person,
          authors: build_list(1, :author, person: nil),
          narrators: build_list(1, :narrator, person: nil)
        )

      book_one = insert(:book, book_authors: [%{author_id: author.id}])
      %{book: book_two} = insert(:media, media_narrators: [%{narrator_id: narrator.id}])

      Index.insert!(:person, person.id)
      Index.insert!(:book, book_one.id)
      Index.insert!(:book, book_two.id)

      person_record = fetch_record(person)
      book_one_record = fetch_record(book_one)
      book_two_record = fetch_record(book_two)

      assert %{primary: primary, secondary: ^person_name} = person_record
      assert primary =~ author.name
      assert primary =~ narrator.name

      %{secondary: secondary, tertiary: tertiary} = book_one_record
      assert secondary =~ author.name
      assert tertiary =~ person.name

      %{secondary: secondary, tertiary: tertiary} = book_two_record
      assert secondary =~ narrator.name
      assert tertiary =~ person.name

      {:ok, _person} =
        People.update_person(person, %{
          name: "PersonName",
          authors: [%{id: author.id, name: "AuthorName"}],
          narrators: [%{id: narrator.id, name: "NarratorName"}]
        })

      assert :ok = Index.update!(:person, person.id)

      person_record = fetch_record(person)
      book_one_record = fetch_record(book_one)
      book_two_record = fetch_record(book_two)

      assert %{primary: primary, secondary: "PersonName"} = person_record
      refute primary =~ author.name
      refute primary =~ narrator.name
      assert primary =~ "AuthorName"
      assert primary =~ "NarratorName"

      %{secondary: secondary, tertiary: tertiary} = book_one_record
      refute secondary =~ author.name
      refute tertiary =~ person.name
      assert secondary =~ "AuthorName"
      assert tertiary =~ "PersonName"

      %{secondary: secondary, tertiary: tertiary} = book_two_record
      refute secondary =~ narrator.name
      refute tertiary =~ person.name
      assert secondary =~ "NarratorName"
      assert tertiary =~ "PersonName"
    end
  end

  describe "update(:series, id)" do
    test "deletes the record if all books are removed" do
      [book1, book2] = books = insert_pair(:book, series_books: [])
      Enum.each(books, &Index.insert!(:book, &1.id))

      %{name: series_name, series_books: [%{id: series_book_id1}, %{id: series_book_id2}]} =
        series =
        insert(:series,
          series_books: [
            %{book_id: book1.id, book_number: 1},
            %{book_id: book2.id, book_number: 2}
          ]
        )

      assert :ok = Index.insert!(:series, series.id)

      assert %{primary: ^series_name} = fetch_record(series)

      {:ok, _updated_series} =
        Books.update_series(series, %{
          series_books_drop: [0, 1],
          series_books: %{
            0 => %{id: series_book_id1},
            1 => %{id: series_book_id2}
          }
        })

      assert :ok = Index.update!(:series, series.id)

      assert nil == fetch_record(series)
    end
  end

  defp fetch_record(struct) do
    reference = Reference.new(struct)

    Repo.one(
      from record in Record,
        where: record.reference == type(^reference, Reference.Type)
    )
  end
end
