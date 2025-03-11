defmodule Ambry.SearchTest do
  use Ambry.DataCase

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.People.Person
  alias Ambry.Search

  describe "search/1" do
    test "returns book by title" do
      %{id: id, title: book_title} = :book |> insert() |> with_search_index()

      assert [%{id: ^id}] = Search.search(book_title)
    end

    test "returns book (and series) by series name" do
      book =
        :book
        |> insert(series_books: [build(:series_book, series: build(:series))])
        |> with_search_index()

      %{id: id, series_books: [%{series: %{id: series_id, name: series_name}}]} = book

      assert results = Search.search(series_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, series_id])
    end

    test "returns book by author name" do
      book =
        :book
        |> insert(
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{name: author_name}}]} = book

      assert [%{id: ^id}] = Search.search(author_name)
    end

    test "returns book by author person name" do
      book =
        :book
        |> insert(
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}}]} = book

      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns book by media narrator name" do
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{book: %{id: id}, media_narrators: [%{narrator: %{name: narrator_name}}]} = media

      assert [%{id: ^id}] = Search.search(narrator_name)
    end

    test "returns book by media narrator person name" do
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{book: %{id: id}, media_narrators: [%{narrator: %{person: %{name: person_name}}}]} = media

      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns person by name" do
      %{id: id, name: person_name} = :person |> insert() |> with_search_index()

      assert [%{id: ^id}] = Search.search(person_name)
    end

    test "returns person by author name" do
      %{id: id, authors: [%{name: author_name}]} =
        :person |> insert(authors: [build(:author)]) |> with_search_index()

      assert [%{id: ^id}] = Search.search(author_name)
    end

    test "returns person by narrator name" do
      %{id: id, narrators: [%{name: narrator_name}]} =
        :person |> insert(narrators: [build(:narrator)]) |> with_search_index()

      assert [%{id: ^id}] = Search.search(narrator_name)
    end

    test "returns series (and book) by author name" do
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{
        id: book_id,
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{name: author_name}}]
      } = book

      assert results = Search.search(author_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, book_id])
    end

    test "returns series (and book) by author person name" do
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{
        id: book_id,
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{person: %{name: person_name}}}]
      } = book

      assert results = Search.search(person_name)
      result_ids = results |> Enum.map(& &1.id) |> Enum.sort()
      assert result_ids == Enum.sort([id, book_id])
    end
  end

  describe "find_first/2" do
    test "returns book by title" do
      %{id: id, title: book_title} = :book |> insert() |> with_search_index()
      assert %{id: ^id} = Search.find_first(book_title, Book)
    end

    test "returns book by series name" do
      book =
        :book
        |> insert(series_books: [build(:series_book, series: build(:series))])
        |> with_search_index()

      %{id: id, series_books: [%{series: %{name: series_name}}]} = book

      assert %{id: ^id} = Search.find_first(series_name, Book)
    end

    test "returns book by author name" do
      book =
        :book
        |> insert(
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{name: author_name}}]} = book

      assert %{id: ^id} = Search.find_first(author_name, Book)
    end

    test "returns book by author person name" do
      book =
        :book
        |> insert(
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{id: id, book_authors: [%{author: %{person: %{name: person_name}}}]} = book

      assert %{id: ^id} = Search.find_first(person_name, Book)
    end

    test "returns book by media narrator name" do
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{book: %{id: id}, media_narrators: [%{narrator: %{name: narrator_name}}]} = media

      assert %{id: ^id} = Search.find_first(narrator_name, Book)
    end

    test "returns book by media narrator person name" do
      media =
        :media
        |> insert(
          book: build(:book),
          media_narrators: [
            build(:media_narrator, narrator: build(:narrator, person: build(:person)))
          ]
        )
        |> with_search_index()

      %{
        book: %{id: id},
        media_narrators: [%{narrator: %{person: %{name: person_name}}}]
      } = media

      assert %{id: ^id} = Search.find_first(person_name, Book)
    end

    test "returns person by name" do
      %{id: id, name: person_name} = :person |> insert() |> with_search_index()

      assert %{id: ^id} = Search.find_first(person_name, Person)
    end

    test "returns person by author name" do
      %{id: id, authors: [%{name: author_name}]} =
        :person |> insert(authors: [build(:author)]) |> with_search_index()

      assert %{id: ^id} = Search.find_first(author_name, Person)
    end

    test "returns person by narrator name" do
      %{id: id, narrators: [%{name: narrator_name}]} =
        :person |> insert(narrators: [build(:narrator)]) |> with_search_index()

      assert %{id: ^id} = Search.find_first(narrator_name, Person)
    end

    test "returns series by name" do
      book =
        :book
        |> insert(series_books: [build(:series_book, series: build(:series))])
        |> with_search_index()

      %{series_books: [%{series: %{id: id, name: series_name}}]} = book

      assert %{id: ^id} = Search.find_first(series_name, Series)
    end

    test "returns series by author name" do
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{name: author_name}}]
      } = book

      assert %{id: ^id} = Search.find_first(author_name, Series)
    end

    test "returns series by author person name" do
      book =
        :book
        |> insert(
          series_books: [build(:series_book, series: build(:series))],
          book_authors: [build(:book_author, author: build(:author, person: build(:person)))]
        )
        |> with_search_index()

      %{
        series_books: [%{series: %{id: id}}],
        book_authors: [%{author: %{person: %{name: person_name}}}]
      } = book

      assert %{id: ^id} = Search.find_first(person_name, Series)
    end
  end
end
