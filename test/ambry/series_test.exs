defmodule Ambry.SeriesTest do
  use Ambry.DataCase

  import Ambry.{BooksFixtures, SeriesFixtures}

  alias Ambry.Series

  describe "list_series/0" do
    test "returns the first 10 series sorted by name" do
      Enum.each(1..11, fn _ ->
        series_fixture()
      end)

      {returned_series, has_more?} = Series.list_series()

      assert has_more?
      assert length(returned_series) == 10
    end
  end

  describe "list_series/1" do
    test "accepts an offset" do
      Enum.each(1..11, fn _ ->
        series_fixture()
      end)

      {returned_series, has_more?} = Series.list_series(10)

      refute has_more?
      assert length(returned_series) == 1
    end
  end

  describe "list_series/2" do
    test "accepts a limit" do
      Enum.each(1..6, fn _ ->
        series_fixture()
      end)

      {returned_series, has_more?} = Series.list_series(0, 5)

      assert has_more?
      assert length(returned_series) == 5
    end
  end

  describe "list_series/3" do
    test "accepts a filter that searches by name" do
      [_, _, %{id: id, name: name}, _, _] =
        Enum.map(1..5, fn _ ->
          series_fixture()
        end)

      {[matched], has_more?} = Series.list_series(0, 10, name)

      refute has_more?
      assert matched.id == id
    end
  end

  describe "get_series!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Series.get_series!(-1)
      end
    end

    test "returns the series with the given id" do
      %{id: id} = series = series_fixture()
      assert %Series.Series{id: ^id} = Series.get_series!(series.id)
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

    test "creates a series with a name" do
      name = unique_series_name()
      {:ok, series} = Series.create_series(valid_series_attributes(name: name))

      assert series.name == name
    end

    test "creates a series with book associations" do
      %{id: book_id} = book_fixture()

      {:ok, series} =
        Series.create_series(
          valid_series_attributes(series_books: [%{book_id: book_id, book_number: 1}])
        )

      assert [%{book_id: ^book_id}] = series.series_books
    end
  end

  describe "update_series/2" do
    test "updates a series name" do
      series = series_fixture()
      new_name = "New Series Name"

      {:ok, updated_series} = Series.update_series(series, %{name: new_name})

      assert updated_series.name == new_name
    end
  end

  describe "delete_series/1" do
    test "deletes a series" do
      series = series_fixture()

      {:ok, _deleted_series} = Series.delete_series(series)

      assert_raise Ecto.NoResultsError, fn ->
        Series.get_series!(series.id)
      end
    end
  end

  describe "change_series/1" do
    test "returns an unchanged changeset for a series" do
      series = series_fixture()

      changeset = Series.change_series(series)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_series/2" do
    test "returns a changeset for a series" do
      series = series_fixture()

      changeset = Series.change_series(series, %{name: "New Name"})

      assert %Ecto.Changeset{valid?: true} = changeset
    end
  end

  describe "get_series_with_books!/1" do
    test "gets a series and all of its books" do
      %{id: book_id} = book_fixture()
      %{id: id} = series_fixture(series_books: [%{book_id: book_id, book_number: 1}])

      series = Series.get_series_with_books!(id)

      assert %Series.Series{
               series_books: [
                 %Series.SeriesBook{book: %Ambry.Books.Book{id: ^book_id}}
               ]
             } = series
    end
  end

  describe "search/1" do
    test "searches for series by name" do
      Enum.each(1..3, fn _ ->
        series_fixture()
      end)

      list = Series.search("Series")

      assert [
               {_, %Series.Series{}},
               {_, %Series.Series{}},
               {_, %Series.Series{}}
             ] = list
    end
  end

  describe "search/2" do
    test "accepts a limit" do
      Enum.each(1..3, fn _ ->
        series_fixture()
      end)

      list = Series.search("Series", 2)

      assert [
               {_, %Series.Series{}},
               {_, %Series.Series{}}
             ] = list
    end
  end

  describe "for_select/0" do
    test "returns all series names and ids only" do
      Enum.each(1..3, fn _ ->
        series_fixture()
      end)

      list = Series.for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
