defmodule Ambry.BooksTest do
  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.PubSub.AsyncBroadcast

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

    test "schedules a job to broadcast a PubSub message" do
      params = params_for(:book, series_books: [], book_authors: [])

      assert {:ok, book} = Books.create_book(params)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.BookCreated",
                        "message" => %{
                          "broadcast_topics" => ["book-created:*"],
                          "id" => book.id
                        }
                      }
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
      %{book_authors: books_authors} = book = insert(:book)

      {:ok, updated_book} =
        Books.update_book(
          book,
          %{
            book_authors_drop: [0],
            book_authors: books_authors |> Enum.with_index(&{&2, %{id: &1.id}}) |> Map.new()
          }
        )

      assert %{book_authors: new_book_authors} = updated_book
      assert length(new_book_authors) == length(books_authors) - 1
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
      %{series_books: series_books} = book = insert(:book)

      {:ok, updated_book} =
        Books.update_book(
          book,
          %{
            series_books_drop: [0],
            series_books: series_books |> Enum.with_index(&{&2, %{id: &1.id}}) |> Map.new()
          }
        )

      assert %{series_books: new_series_books} = updated_book
      assert length(new_series_books) == length(series_books) - 1
    end

    test "schedules a job to broadcast a PubSub message" do
      book = insert(:book)
      %{title: new_title} = params_for(:book)

      {:ok, updated_book} = Books.update_book(book, %{title: new_title})

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.BookUpdated",
                        "message" => %{
                          "broadcast_topics" => [
                            "book-updated:#{updated_book.id}",
                            "book-updated:*"
                          ],
                          "id" => updated_book.id
                        }
                      }
    end
  end

  describe "delete_book/1" do
    test "deletes a book" do
      book = insert(:book)

      {:ok, _book} = Books.delete_book(book)

      assert_raise Ecto.NoResultsError, fn ->
        Books.get_book!(book.id)
      end
    end

    test "schedules a job to broadcast a PubSub message" do
      book = insert(:book)

      {:ok, deleted_book} = Books.delete_book(book)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.BookDeleted",
                        "message" => %{
                          "broadcast_topics" => [
                            "book-deleted:#{deleted_book.id}",
                            "book-deleted:*"
                          ],
                          "id" => deleted_book.id
                        }
                      }
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

  describe "books_for_select/0" do
    test "returns all book titles and ids only" do
      insert_list(3, :book)

      list = Books.books_for_select()

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

  describe "list_series/0" do
    test "returns the first 10 series sorted by name" do
      insert_list(11, :series)

      {returned_series, has_more?} = Books.list_series()

      assert has_more?
      assert length(returned_series) == 10
    end
  end

  describe "list_series/1" do
    test "accepts an offset" do
      insert_list(11, :series)

      {returned_series, has_more?} = Books.list_series(10)

      refute has_more?
      assert length(returned_series) == 1
    end
  end

  describe "list_series/2" do
    test "accepts a limit" do
      insert_list(6, :series)

      {returned_series, has_more?} = Books.list_series(0, 5)

      assert has_more?
      assert length(returned_series) == 5
    end
  end

  describe "list_series/3" do
    test "accepts a 'search' filter that searches by series name" do
      [_, _, %{id: id, name: name}, _, _] = insert_list(5, :series)

      {[matched], has_more?} = Books.list_series(0, 10, %{search: name})

      refute has_more?
      assert matched.id == id
    end
  end

  describe "list_series/4" do
    test "allows sorting results by any field on the schema" do
      %{id: series1_id} = insert(:series, name: "Apple")
      %{id: series2_id} = insert(:series, name: "Banana")
      %{id: series3_id} = insert(:series, name: "Carrot")

      {series, false} = Books.list_series(0, 10, %{}, :name)

      assert [
               %{id: ^series1_id},
               %{id: ^series2_id},
               %{id: ^series3_id}
             ] = series

      {series, false} = Books.list_series(0, 10, %{}, {:desc, :name})

      assert [
               %{id: ^series3_id},
               %{id: ^series2_id},
               %{id: ^series1_id}
             ] = series
    end
  end

  describe "count_series/0" do
    test "returns the number of series in the database" do
      insert_list(3, :series)

      assert 3 = Books.count_series()
    end
  end

  describe "get_series!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Books.get_series!(-1)
      end
    end

    test "returns the series with the given id" do
      %{id: id} = insert(:series)
      assert %Books.Series{id: ^id} = Books.get_series!(id)
    end
  end

  describe "create_series/1" do
    test "requires name to be set" do
      {:error, changeset} = Books.create_series(%{})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates name when given" do
      {:error, changeset} = Books.create_series(%{name: ""})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a series when given valid attributes" do
      %{name: name} = params = params_for(:series)

      assert {:ok, series} = Books.create_series(params)

      assert %{name: ^name} = series
    end

    test "can create a series with nested book associations" do
      %{id: book_id} = insert(:book, series_books: [])

      %{name: name} = series_params = params_for(:series)

      %{book_number: book_number} =
        series_book_params = params_for(:series_book, book_id: book_id)

      params = Map.put(series_params, :series_books, [series_book_params])

      assert {:ok, series} = Books.create_series(params)

      book_number_decimal = Decimal.new(book_number)

      assert %{
               name: ^name,
               series_books: [
                 %{
                   book_number: ^book_number_decimal,
                   book_id: ^book_id
                 }
               ]
             } = series
    end

    test "schedules a job to broadcast a PubSub message" do
      params = params_for(:series)

      assert {:ok, series} = Books.create_series(params)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.SeriesCreated",
                        "message" => %{
                          "broadcast_topics" => ["series-created:*"],
                          "id" => series.id
                        }
                      }
    end
  end

  describe "update_series/2" do
    test "updates a series name" do
      series = insert(:series)
      %{name: new_name} = params_for(:series)

      {:ok, updated_series} = Books.update_series(series, %{name: new_name})

      assert updated_series.name == new_name
    end

    test "schedules a job to broadcast a PubSub message" do
      series = insert(:series)
      %{name: new_name} = params_for(:series)

      {:ok, updated_series} = Books.update_series(series, %{name: new_name})

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.SeriesUpdated",
                        "message" => %{
                          "broadcast_topics" => [
                            "series-updated:#{updated_series.id}",
                            "series-updated:*"
                          ],
                          "id" => updated_series.id
                        }
                      }
    end
  end

  describe "delete_series/1" do
    test "deletes a series" do
      series = insert(:series)

      {:ok, _series} = Books.delete_series(series)

      assert_raise Ecto.NoResultsError, fn ->
        Books.get_series!(series.id)
      end
    end

    test "schedules a job to broadcast a PubSub message" do
      series = insert(:series)

      {:ok, deleted_series} = Books.delete_series(series)

      assert_enqueued worker: AsyncBroadcast,
                      args: %{
                        "module" => "Elixir.Ambry.Books.PubSub.SeriesDeleted",
                        "message" => %{
                          "broadcast_topics" => [
                            "series-deleted:#{deleted_series.id}",
                            "series-deleted:*"
                          ],
                          "id" => deleted_series.id
                        }
                      }
    end
  end

  describe "change_series/1" do
    test "returns an unchanged changeset for a series" do
      series = insert(:series)

      changeset = Books.change_series(series)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_series/2" do
    test "returns a changeset for a series" do
      series = insert(:series)
      %{name: new_name} = params_for(:series)

      changeset = Books.change_series(series, %{name: new_name})

      assert %Ecto.Changeset{valid?: true} = changeset
      assert new_name == Ecto.Changeset.get_change(changeset, :name)
    end
  end

  describe "get_series_with_books!/1" do
    test "gets a series and all of its books" do
      %{id: book_id, series_books: [%{series_id: series_id} | _other_series]} = insert(:book)

      series = Books.get_series_with_books!(series_id)

      assert %Books.Series{
               series_books: [
                 %Books.SeriesBook{book: %Ambry.Books.Book{id: ^book_id}}
               ]
             } = series
    end
  end

  describe "series_for_select/0" do
    test "returns all series names and ids only" do
      insert_list(3, :series)

      list = Books.series_for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
