defmodule Ambry.Search.PickerTest do
  @moduledoc """
  What a typeahead has to do that a list filter does not.

  A list is already narrowed and sorted by the operator, so its filter can be
  strict. A box somebody is typing into is the opposite: the word is usually
  half-finished, one of the words is usually wrong, and the whole answer is
  which three rows go at the top.
  """

  use Ambry.DataCase

  alias Ambry.Books
  alias Ambry.Media
  alias Ambry.People

  setup do
    person = insert(:person, name: "Brandon Sanderson")
    author = insert(:author, name: "Brandon Sanderson", person: person)
    series = insert(:series, name: "The Stormlight Archive", series_books: [])

    book =
      insert(:book,
        title: "The Way of Kings",
        book_authors: [%{author_id: author.id}],
        series_books: [%{series_id: series.id, book_number: 1}]
      )

    universe =
      insert(:universe, name: "The Cosmere", book_universes: [%{book_id: book.id}])

    media = insert(:media, book: book)

    %{book: book, media: media, person: person, series: series, universe: universe}
  end

  describe "half-typed words" do
    test "the recording picker matches a prefix", %{book: book} do
      # This is the regression that moving the admin list filters onto the
      # index introduced: the pickers were sharing the list's filter, where
      # "sander" is a whole word that matches nothing.
      assert [%{id: _}] = Media.search_media("sander", 10)
      assert [%{id: _}] = Media.search_book_media(book.id, "sander", 10)
    end

    test "the person picker matches a prefix", %{person: person} do
      person_id = person.id
      assert [%{id: ^person_id}] = People.search_people("sander", 10)
    end

    test "the series picker matches a prefix", %{series: series} do
      series_id = series.id
      assert [{_name, ^series_id}] = Books.search_series("stormligh", 10)
    end

    test "the universe picker matches a prefix", %{universe: universe} do
      universe_id = universe.id
      assert [{_name, ^universe_id}] = Books.search_universes("cosmer", 10)
    end
  end

  describe "a term that misses" do
    test "does not empty the recording picker" do
      assert [_recording] = Media.search_media("kings audiobook", 10)
    end
  end

  describe "what the index adds over a name column" do
    test "a series is findable by its author", %{series: series} do
      series_id = series.id
      assert [{_name, ^series_id}] = Books.search_series("sanderson", 10)
    end

    test "a universe is findable by who writes in it", %{universe: universe} do
      universe_id = universe.id
      assert [{_name, ^universe_id}] = Books.search_universes("sanderson", 10)
    end

    test "a person is findable by a name they publish under" do
      # Their own name is not "Sanderson" — the pen name is.
      person = insert(:person, name: "Ty Franck", authors: [build(:author, name: "James Corey")])
      person_id = person.id

      assert [%{id: ^person_id}] = People.search_people("james corey", 10)
      assert [%{id: ^person_id}] = People.search_people("ty franck", 10)
    end
  end

  describe "an empty box" do
    test "shows the first page rather than nothing" do
      refute Books.search_series("", 10) == []
      refute Books.search_universes("", 10) == []
      refute People.search_people("", 10) == []
      refute Media.search_media("", 10) == []
    end
  end
end
