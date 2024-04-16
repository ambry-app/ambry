defmodule Ambry.SearchTest do
  use Ambry.DataCase

  import Ambry.Search.IndexFactory

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People.Person
  alias Ambry.Search

  describe "search/1" do
    test "returns book by title" do
      %{id: id, title: book_title} = book = insert(:book)
      insert_index!(book)

      assert [%{id: ^id}] = Search.search(book_title)
    end

    test "returns book (and series) by series name" do
      %{id: id, series_books: [%{series: %{id: series_id, name: series_name}} | _rest]} =
        book = insert(:book)

      insert_index!(book)

      assert results = Search.search(series_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, series_id])
    end

    test "returns book by author name" do
      %{id: id, book_authors: [%{author: %{name: author_name}} | _rest]} =
        book = insert(:book, series_books: [])

      insert_index!(book)
      assert [%{id: ^id}] = Search.search(author_name)
    end

    test "returns book by author person name" do
      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}} | _rest]} =
        book = insert(:book, series_books: [])

      insert_index!(book)

      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns book by media narrator name" do
      %{book: %{id: id} = book, media_narrators: [%{narrator: %{name: narrator_name}} | _rest]} =
        insert(:media)

      insert_index!(book)

      assert [%{id: ^id}] = Search.search(narrator_name)
    end

    test "returns book by media narrator person name" do
      %{
        book: %{id: id} = book,
        media_narrators: [%{narrator: %{person: %{name: person_name}}} | _rest]
      } = insert(:media)

      insert_index!(book)

      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns person by name" do
      %{id: id, name: person_name} = person = insert(:person)
      insert_index!(person)
      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns person by author name" do
      %{name: author_name, person: %{id: id} = person} = insert(:author)
      insert_index!(person)
      assert [%{id: ^id}] = Search.search(author_name)
    end

    test "returns person by narrator name" do
      %{name: narrator_name, person: %{id: id} = person} = insert(:narrator)
      insert_index!(person)
      assert [%{id: ^id}] = Search.search(narrator_name)
    end

    test "returns series (and book) by author name" do
      %{
        id: book_id,
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{name: author_name}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)

      assert results = Search.search(author_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, book_id])
    end

    test "returns series (and book) by author person name" do
      %{
        id: book_id,
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{person: %{name: person_name}}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)

      assert results = Search.search(person_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, book_id])
    end
  end

  describe "find_first/2" do
    test "returns book by title" do
      %{id: id, title: book_title} = book = insert(:book)
      insert_index!(book)
      assert %{id: ^id} = Search.find_first(book_title, Book)
    end

    test "returns book by series name" do
      %{id: id, series_books: [%{series: %{name: series_name}} | _rest]} = book = insert(:book)
      insert_index!(book)
      assert %{id: ^id} = Search.find_first(series_name, Book)
    end

    test "returns book by author name" do
      %{id: id, book_authors: [%{author: %{name: author_name}} | _rest]} =
        book = insert(:book, series_books: [])

      insert_index!(book)
      assert %{id: ^id} = Search.find_first(author_name, Book)
    end

    test "returns book by author person name" do
      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}} | _rest]} =
        book = insert(:book, series_books: [])

      insert_index!(book)

      assert %{id: ^id} = Search.find_first(person_name, Book)
    end

    test "returns book by media narrator name" do
      %{book: %{id: id} = book, media_narrators: [%{narrator: %{name: narrator_name}} | _rest]} =
        insert(:media)

      insert_index!(book)
      assert %{id: ^id} = Search.find_first(narrator_name, Book)
    end

    test "returns book by media narrator person name" do
      %{
        book: %{id: id} = book,
        media_narrators: [%{narrator: %{person: %{name: person_name}}} | _rest]
      } = insert(:media)

      insert_index!(book)

      assert %{id: ^id} = Search.find_first(person_name, Book)
    end

    test "returns person by name" do
      %{id: id, name: person_name} = person = insert(:person)
      insert_index!(person)
      assert %{id: ^id} = Search.find_first(person_name, Person)
    end

    test "returns person by author name" do
      %{name: author_name, person: %{id: id} = person} = insert(:author)
      insert_index!(person)
      assert %{id: ^id} = Search.find_first(author_name, Person)
    end

    test "returns person by narrator name" do
      %{name: narrator_name, person: %{id: id} = person} = insert(:narrator)
      insert_index!(person)
      assert %{id: ^id} = Search.find_first(narrator_name, Person)
    end

    test "returns series by name" do
      %{series_books: [%{series: %{id: id, name: series_name}} | _rest]} = book = insert(:book)
      insert_index!(book)
      assert %{id: ^id} = Search.find_first(series_name, Series)
    end

    test "returns series by author name" do
      %{
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{name: author_name}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)

      assert %{id: ^id} = Search.find_first(author_name, Series)
    end

    test "returns series by author person name" do
      %{
        series_books: [%{series: %{id: id} = series} | _rest1],
        book_authors: [%{author: %{person: %{name: person_name}}} | _rest2]
      } = insert(:book)

      # NOTE: this also indexes the book
      insert_index!(series)

      assert %{id: ^id} = Search.find_first(person_name, Series)
    end
  end
end
