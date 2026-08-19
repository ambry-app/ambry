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

    media =
      insert(:media,
        book: book,
        media_narrators: [
          build(:media_narrator, narrator: build(:narrator, person: build(:person)))
        ]
      )

    %{book: book, media: media, person: person, series: series, universe: universe}
  end

  describe "half-typed words" do
    test "the recording picker matches a prefix" do
      # This is the regression that moving the admin list filters onto the
      # index introduced: the pickers were sharing the list's filter, where
      # "sander" is a whole word that matches nothing.
      assert [%{id: _}] = Media.search_media("sander", 10)
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

  describe "pen names" do
    test "an author picker finds a pen name" do
      insert(:author, name: "James S.A. Corey", person: build(:person, name: "Ty Franck"))

      assert [%{label: "James S.A. Corey"}] = People.search_authors("corey", 10)
    end

    test "and finds it by the person behind it" do
      # The pen name is still the answer — it is what goes on the book — but
      # the human is often how you recognise which one you meant.
      insert(:author, name: "James S.A. Corey", person: build(:person, name: "Ty Franck"))

      assert [%{label: "James S.A. Corey"}] = People.search_authors("ty franck", 10)
    end

    test "a narrator picker does the same" do
      insert(:narrator, name: "R.C. Bray", person: build(:person, name: "Robert Bray"))

      assert [%{label: "R.C. Bray"}] = People.search_narrators("robert", 10)
    end

    test "an author publishing under their own name is listed once" do
      insert(:author, name: "Ursula Le Guin", person: build(:person, name: "Ursula Le Guin"))

      assert [%{label: "Ursula Le Guin"}] = People.search_authors("le guin", 10)
    end

    test "renaming the person rewrites the pen name's record" do
      person = insert(:person, name: "Ty Franck")
      insert(:author, name: "James S.A. Corey", person: person)

      assert [_found] = People.search_authors("ty franck", 10)

      {:ok, _person} = People.update_person(person, %{name: "Daniel Abraham"})

      assert People.search_authors("ty franck", 10) == []
      assert [%{label: "James S.A. Corey"}] = People.search_authors("abraham", 10)
    end
  end

  describe "the recording picker ranks" do
    setup do
      # Two books whose recordings sort the wrong way round alphabetically:
      # the match is "Zeta", and "Alpha" only shares the author.
      person = insert(:person, name: "Ada Rivers")
      author = insert(:author, name: "Ada Rivers", person: person)

      for title <- ["Alpha of the Fold", "Zeta Protocol"] do
        book = insert(:book, title: title, book_authors: [%{author_id: author.id}])
        insert(:media, book: book)
      end

      :ok
    end

    test "best first, not alphabetically first" do
      # This asked `Query.ids/3`, which drops the ORDER BY for the admin
      # lists, then sorted by book title and took the first N — so the ten
      # shown were the alphabetically-first ten of the candidates, and the
      # best match was routinely not among them.
      assert ["Zeta Protocol" | _rest] = labels(Media.search_media("zeta", 10))
    end

    test "and the limit cuts from the bottom of the ranking" do
      assert ["Zeta Protocol"] = labels(Media.search_media("zeta protocol", 1))
    end

    test "the recordings of one book stay together, in part order" do
      book = insert(:book, title: "Kaiju Preservation Society")
      group = insert(:recording_group, book: book, parts_total: 2)

      insert(:media, book: book, part_number: 2, recording_group_id: group.id)
      insert(:media, book: book, part_number: 1, recording_group_id: group.id)

      assert [
               "Kaiju Preservation Society (Part 1 of 2)",
               "Kaiju Preservation Society (Part 2 of 2)"
             ] = labels(Media.search_media("kaiju", 10))
    end
  end

  describe "an empty box" do
    test "shows the first page rather than nothing" do
      refute Books.search_series("", 10) == []
      refute Books.search_universes("", 10) == []
      refute People.search_people("", 10) == []
      refute People.search_authors("", 10) == []
      refute People.search_narrators("", 10) == []
      refute Media.search_media("", 10) == []
    end
  end

  defp labels(options), do: Enum.map(options, & &1.label)
end
