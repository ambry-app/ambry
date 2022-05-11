defmodule Ambry.BooksTest do
  use Ambry.DataCase

  import ExUnit.CaptureLog

  alias Ambry.Books

  describe "list_books/0" do
    test "returns the first 10 books sorted by title" do
      insert_list(11, :book)

      {returned_books, has_more?} = Books.list_books()

      assert has_more?
      assert length(returned_books) == 10
    end
  end

  describe "list_books/1" do
    test "accepts an offset" do
      insert_list(11, :book)

      {returned_books, has_more?} = Books.list_books(10)

      refute has_more?
      assert length(returned_books) == 1
    end
  end

  describe "list_books/2" do
    test "accepts a limit" do
      insert_list(6, :book)

      {returned_books, has_more?} = Books.list_books(0, 5)

      assert has_more?
      assert length(returned_books) == 5
    end
  end

  describe "list_books/3" do
    test "accepts a 'search' filter that searches by book title" do
      [_, _, %{id: id, title: title}, _, _] = insert_list(5, :book)

      {[matched], has_more?} = Books.list_books(0, 10, %{search: title})

      refute has_more?
      assert matched.id == id
    end
  end

  describe "list_books/4" do
    test "allows sorting results by any field on the schema" do
      %{id: book1_id} = insert(:book, title: "Apple")
      %{id: book2_id} = insert(:book, title: "Banana")
      %{id: book3_id} = insert(:book, title: "Carrot")

      {books, false} = Books.list_books(0, 10, %{}, :title)

      assert [
               %{id: ^book1_id},
               %{id: ^book2_id},
               %{id: ^book3_id}
             ] = books

      {books, false} = Books.list_books(0, 10, %{}, {:desc, :title})

      assert [
               %{id: ^book3_id},
               %{id: ^book2_id},
               %{id: ^book1_id}
             ] = books
    end
  end

  describe "count_books/0" do
    test "returns the number of books in the database" do
      insert_list(3, :book)

      assert 3 = Books.count_books()
    end
  end

  describe "get_book!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Books.get_book!(-1)
      end
    end

    test "returns the book with the given id" do
      %{id: id} = insert(:book)

      assert %Books.Book{id: ^id} = Books.get_book!(id)
    end
  end

  describe "create_book/1" do
    test "requires title and published to be set" do
      {:error, changeset} = Books.create_book(%{})

      assert %{
               title: ["can't be blank"],
               published: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a book when given valid attributes" do
      %{title: title} = params = params_for(:book, series_books: [], book_authors: [])

      assert {:ok, book} = Books.create_book(params)

      assert %{title: ^title} = book
    end

    test "can create nested book authors" do
      %{id: author_id} = insert(:author)

      %{title: title} =
        params = params_for(:book, series_books: [], book_authors: [%{author_id: author_id}])

      assert {:ok, book} = Books.create_book(params)

      assert %{title: ^title, book_authors: [%{author_id: ^author_id}]} = book
    end

    test "can create nested series books" do
      %{id: series_id} = insert(:series)

      %{title: title} =
        params =
        params_for(:book,
          series_books: [%{series_id: series_id, book_number: 1}],
          book_authors: []
        )

      assert {:ok, book} = Books.create_book(params)

      assert %{title: ^title, series_books: [%{series_id: ^series_id}]} = book
    end
  end

  describe "update_book/2" do
    test "updates a book" do
      book = insert(:book)
      %{title: new_title} = params_for(:book)

      {:ok, updated_book} = Books.update_book(book, %{title: new_title})

      assert updated_book.title == new_title
    end

    test "updates nested book authors" do
      %{id: new_author_id} = insert(:author)
      %{book_authors: [existing_book_author | rest_book_authors]} = book = insert(:book)

      assert existing_book_author.author_id != new_author_id

      {:ok, updated_book} =
        Books.update_book(book, %{
          book_authors: [
            %{id: existing_book_author.id, author_id: new_author_id}
            | Enum.map(rest_book_authors, &%{id: &1.id})
          ]
        })

      assert %{
               book_authors: [
                 %{
                   author_id: ^new_author_id
                 }
                 | _rest
               ]
             } = updated_book
    end

    test "deletes nested book authors" do
      %{book_authors: [book_author | rest_book_authors]} = book = insert(:book)

      {:ok, updated_book} =
        Books.update_book(
          book,
          %{
            book_authors: [
              %{id: book_author.id, delete: true} | Enum.map(rest_book_authors, &%{id: &1.id})
            ]
          }
        )

      assert %{book_authors: book_authors} = updated_book
      assert length(book_authors) == length(rest_book_authors)
    end

    test "updates nested series books" do
      %{id: new_series_id} = insert(:series)
      %{series_books: [existing_series_book | rest_series_books]} = book = insert(:book)

      assert existing_series_book.series_id != new_series_id

      {:ok, updated_book} =
        Books.update_book(book, %{
          series_books: [
            %{id: existing_series_book.id, series_id: new_series_id}
            | Enum.map(rest_series_books, &%{id: &1.id})
          ]
        })

      assert %{
               series_books: [
                 %{
                   series_id: ^new_series_id
                 }
                 | _rest
               ]
             } = updated_book
    end

    test "deletes nested series books" do
      %{series_books: [series_book | rest_series_books]} = book = insert(:book)

      {:ok, updated_book} =
        Books.update_book(
          book,
          %{
            series_books: [
              %{id: series_book.id, delete: true} | Enum.map(rest_series_books, &%{id: &1.id})
            ]
          }
        )

      assert %{series_books: series_books} = updated_book
      assert length(series_books) == length(rest_series_books)
    end
  end

  describe "delete_book/1" do
    test "deletes a book" do
      book = insert(:book)

      :ok = Books.delete_book(book)

      assert_raise Ecto.NoResultsError, fn ->
        Books.get_book!(book.id)
      end
    end

    test "deletes the image file from disk used by a book" do
      book = insert(:book)

      assert File.exists?(Ambry.Paths.web_to_disk(book.image_path))

      :ok = Books.delete_book(book)

      refute File.exists?(Ambry.Paths.web_to_disk(book.image_path))
    end

    test "does not delete the image file from disk if the same image is used by multiple books" do
      book = insert(:book)
      book2 = insert(:book, image_path: book.image_path)

      assert File.exists?(Ambry.Paths.web_to_disk(book.image_path))

      fun = fn ->
        :ok = Books.delete_book(book2)
      end

      assert capture_log(fun) =~ "Not deleting file because it's still in use"

      assert File.exists?(Ambry.Paths.web_to_disk(book.image_path))
    end

    test "warns if the image file from disk used by a book does not exist" do
      book = insert(:book)

      File.rm!(Ambry.Paths.web_to_disk(book.image_path))

      fun = fn ->
        :ok = Books.delete_book(book)
      end

      assert capture_log(fun) =~ "Couldn't delete file (enoent)"
    end

    test "cannot delete a book if it belongs to an uploaded media" do
      %{book: book} = insert(:media)

      {:error, :has_media} = Books.delete_book(book)
    end
  end

  describe "change_book/1" do
    test "returns an unchanged changeset for a book" do
      book = insert(:book)

      changeset = Books.change_book(book)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_book/2" do
    test "returns a changeset for a book" do
      book = insert(:book)
      %{title: title} = params_for(:book)

      changeset = Books.change_book(book, %{title: title})

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "get_book_with_media!/1" do
    test "gets a book and of its uploaded media" do
      %{id: media_id, book: %{id: book_id}} = insert(:media, status: :ready)

      book = Books.get_book_with_media!(book_id)

      assert %Books.Book{
               media: [
                 %{id: ^media_id}
               ]
             } = book
    end
  end

  describe "get_recent_books/0" do
    test "returns the first 10 books sorted by inserted_at" do
      insert_list(11, :book)

      {returned_books, has_more?} = Books.get_recent_books()

      assert has_more?
      assert length(returned_books) == 10
    end
  end

  describe "get_recent_books/1" do
    test "accepts an offset" do
      insert_list(11, :book)

      {returned_books, has_more?} = Books.get_recent_books(10)

      refute has_more?
      assert length(returned_books) == 1
    end
  end

  describe "get_recent_books/2" do
    test "accepts a limit" do
      insert_list(6, :book)

      {returned_books, has_more?} = Books.get_recent_books(0, 5)

      assert has_more?
      assert length(returned_books) == 5
    end
  end

  describe "search/1" do
    test "searches for book by title" do
      [%{title: title} | _] = insert_list(3, :book)

      list = Books.search(title)

      assert [{_, %Books.Book{}}] = list
    end
  end

  describe "search/2" do
    test "accepts a limit" do
      insert_list(3, :book, title: "Foo Bar Baz")

      list = Books.search("Foo", 2)

      assert [
               {_, %Books.Book{}},
               {_, %Books.Book{}}
             ] = list
    end
  end

  describe "for_select/0" do
    test "returns all book titles and ids only" do
      insert_list(3, :book)

      list = Books.for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end

  describe "get_book_description/1" do
    test "returns a string describing the book" do
      book = insert(:book)
      %{title: title, book_authors: [%{author: %{name: author_name}} | _]} = book

      description = Books.get_book_description(book)

      assert description =~ title
      assert description =~ author_name
    end
  end
end
