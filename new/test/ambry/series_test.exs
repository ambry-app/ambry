defmodule Ambry.SeriesTest do
  use Ambry.DataCase

  alias Ambry.Series

  describe "list_series/0" do
    test "returns the first 10 series sorted by name" do
      insert_list(11, :series)

      {returned_series, has_more?} = Series.list_series()

      assert has_more?
      assert length(returned_series) == 10
    end
  end

  describe "list_series/1" do
    test "accepts an offset" do
      insert_list(11, :series)

      {returned_series, has_more?} = Series.list_series(10)

      refute has_more?
      assert length(returned_series) == 1
    end
  end

  describe "list_series/2" do
    test "accepts a limit" do
      insert_list(6, :series)

      {returned_series, has_more?} = Series.list_series(0, 5)

      assert has_more?
      assert length(returned_series) == 5
    end
  end

  describe "list_series/3" do
    test "accepts a 'search' filter that searches by series name" do
      [_, _, %{id: id, name: name}, _, _] = insert_list(5, :series)

      {[matched], has_more?} = Series.list_series(0, 10, %{search: name})

      refute has_more?
      assert matched.id == id
    end
  end

  describe "list_series/4" do
    test "allows sorting results by any field on the schema" do
      %{id: series1_id} = insert(:series, name: "Apple")
      %{id: series2_id} = insert(:series, name: "Banana")
      %{id: series3_id} = insert(:series, name: "Carrot")

      {series, false} = Series.list_series(0, 10, %{}, :name)

      assert [
               %{id: ^series1_id},
               %{id: ^series2_id},
               %{id: ^series3_id}
             ] = series

      {series, false} = Series.list_series(0, 10, %{}, {:desc, :name})

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

      assert 3 = Series.count_series()
    end
  end

  describe "get_series!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Series.get_series!(-1)
      end
    end

    test "returns the series with the given id" do
      %{id: id} = insert(:series)
      assert %Series.Series{id: ^id} = Series.get_series!(id)
    end
  end

  describe "create_series/1" do
    test "requires name to be set" do
      {:error, changeset} = Series.create_series(%{})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates name when given" do
      {:error, changeset} = Series.create_series(%{name: ""})

      assert %{
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "creates a series when given valid attributes" do
      %{name: name} = params = params_for(:series)

      assert {:ok, series} = Series.create_series(params)

      assert %{name: ^name} = series
    end

    test "can create a series with nested book associations" do
      %{id: book_id} = insert(:book, series_books: [])

      %{name: name} = series_params = params_for(:series)

      %{book_number: book_number} =
        series_book_params = params_for(:series_book, book_id: book_id)

      params = Map.put(series_params, :series_books, [series_book_params])

      assert {:ok, series} = Series.create_series(params)

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
  end

  describe "update_series/2" do
    test "updates a series name" do
      series = insert(:series)
      %{name: new_name} = params_for(:series)

      {:ok, updated_series} = Series.update_series(series, %{name: new_name})

      assert updated_series.name == new_name
    end
  end

  describe "delete_series/1" do
    test "deletes a series" do
      series = insert(:series)

      {:ok, _deleted_series} = Series.delete_series(series)

      assert_raise Ecto.NoResultsError, fn ->
        Series.get_series!(series.id)
      end
    end
  end

  describe "change_series/1" do
    test "returns an unchanged changeset for a series" do
      series = insert(:series)

      changeset = Series.change_series(series)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_series/2" do
    test "returns a changeset for a series" do
      series = insert(:series)
      %{name: new_name} = params_for(:series)

      changeset = Series.change_series(series, %{name: new_name})

      assert %Ecto.Changeset{valid?: true} = changeset
      assert new_name == Ecto.Changeset.get_change(changeset, :name)
    end
  end

  describe "get_series_with_books!/1" do
    test "gets a series and all of its books" do
      %{id: book_id, series_books: [%{series_id: series_id} | _other_series]} = insert(:book)

      series = Series.get_series_with_books!(series_id)

      assert %Series.Series{
               series_books: [
                 %Series.SeriesBook{book: %Ambry.Books.Book{id: ^book_id}}
               ]
             } = series
    end
  end

  describe "search/1" do
    test "searches for series by name" do
      [%{name: name} | _] = insert_list(3, :series)

      list = Series.search(name)

      assert [{_, %Series.Series{}}] = list
    end
  end

  describe "search/2" do
    test "accepts a limit" do
      insert_list(3, :series, name: "Foo Bar Baz")

      list = Series.search("Foo", 2)

      assert [
               {_, %Series.Series{}},
               {_, %Series.Series{}}
             ] = list
    end
  end

  describe "for_select/0" do
    test "returns all series names and ids only" do
      insert_list(3, :series)

      list = Series.for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
