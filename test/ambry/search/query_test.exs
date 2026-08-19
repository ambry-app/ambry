defmodule Ambry.Search.QueryTest do
  @moduledoc """
  The golden queries: a small library, and the searches that have to keep
  working on it.

  Ranking is the one thing that fails quietly — a regression does not raise,
  it just puts the wrong thing first — so these assert on the *top hit* by
  name rather than on membership. When one of them breaks it is because
  somebody changed the weights, the text search configuration, or the joiner,
  and the failure should say which query noticed.

  Every case here is one the old five searches could not all do. The comments
  say which property is being pinned.
  """

  use Ambry.DataCase

  alias Ambry.Search.Query

  setup do
    sanderson = insert(:person, name: "Brandon Sanderson")
    sanderson_author = insert(:author, name: "Brandon Sanderson", person: sanderson)

    stormlight = insert(:series, name: "The Stormlight Archive", series_books: [])

    way_of_kings =
      insert(:book,
        title: "The Way of Kings",
        book_authors: [%{author_id: sanderson_author.id}],
        series_books: [%{series_id: stormlight.id, book_number: 1}]
      )

    mistborn =
      insert(:book,
        title: "Mistborn: The Final Empire",
        book_authors: [%{author_id: sanderson_author.id}]
      )

    # A title whose punctuation is the whole problem: no substring of
    # "Truly, Devious" is "truly devious", which is why the `ILIKE` searches
    # could never find it.
    johnson = insert(:person, name: "Maureen Johnson")
    johnson_author = insert(:author, name: "Maureen Johnson", person: johnson)

    truly_devious =
      insert(:book,
        title: "Truly, Devious",
        book_authors: [%{author_id: johnson_author.id}]
      )

    # A person whose name is unreachable from an ASCII keyboard unless the
    # index folds accents.
    rodriguez = insert(:person, name: "Patricia Rodríguez")
    insert(:narrator, name: "Patricia Rodríguez", person: rodriguez)

    dirisu = insert(:person, name: "Ṣọpẹ́ Dìrísù")
    insert(:narrator, name: "Ṣọpẹ́ Dìrísù", person: dirisu)

    cosmere =
      insert(:universe,
        name: "The Cosmere",
        book_universes: [
          %{book_id: way_of_kings.id},
          %{book_id: mistborn.id}
        ]
      )

    # The British title on the book, the American one on the recording. Both
    # have to find it.
    philosophers_stone = insert(:book, title: "Harry Potter and the Philosopher's Stone")

    insert(:media,
      book: philosophers_stone,
      title: "Harry Potter and the Sorcerer's Stone"
    )

    %{
      way_of_kings: way_of_kings,
      cosmere: cosmere,
      mistborn: mistborn,
      stormlight: stormlight,
      truly_devious: truly_devious,
      philosophers_stone: philosophers_stone,
      sanderson: sanderson,
      rodriguez: rodriguez,
      dirisu: dirisu
    }
  end

  describe "punctuation" do
    test "a comma in the title does not hide the book" do
      assert top("truly devious") == "Truly, Devious"
    end

    test "an apostrophe in the query does not hide the book" do
      assert top("sorcerer's stone") =~ "Philosopher's Stone"
    end
  end

  describe "accents" do
    test "an ASCII spelling finds the accented name" do
      assert top("rodriguez") == "Patricia Rodríguez"
    end

    test "the accented spelling finds it too" do
      assert top("Rodríguez") == "Patricia Rodríguez"
    end

    test "folding is not limited to Latin-1 — Yoruba dot-below included" do
      assert top("sope dirisu") == "Ṣọpẹ́ Dìrísù"
      assert top("Ṣọpẹ́ Dìrísù") == "Ṣọpẹ́ Dìrísù"
    end
  end

  describe "recording title overrides" do
    test "the book is findable under either edition's title" do
      assert top("philosopher's stone") =~ "Philosopher's Stone"
      assert top("sorcerer's stone") =~ "Philosopher's Stone"
    end
  end

  describe "joiner: :any" do
    test "an author's name improves a title match rather than breaking it" do
      # Worth noting what :all already handles: "sanderson kings" finds The
      # Way of Kings under :all, because a record's vector is all three of
      # its columns and both words are in it. The index does not have
      # `by_keywords`' problem of asking one field one question.
      assert top("sanderson kings", joiner: :all) == "The Way of Kings"
    end

    test "a term that misses costs nothing" do
      # A term that appears in no record at all is what breaks :all — and a
      # file's idea of a title routinely carries one.
      assert top("sanderson kings audiobook unabridged", joiner: :all) == nil
      assert top("sanderson kings audiobook unabridged", joiner: :any) == "The Way of Kings"
    end

    test "more matching terms still rank higher" do
      hits = hits("sanderson mistborn", joiner: :any)

      assert hd(hits) == "Mistborn: The Final Empire"
      assert "The Way of Kings" in hits
    end
  end

  describe "joiner: :narrowing" do
    # The picker's policy over the other two, and the answer to the
    # complaint that started all of this: another word is typed in order to
    # *remove* rows, and under `:any` it only ever added them.
    # `:narrowing` is two queries and a rule about which one answers, so it
    # is not something `build/2` can return — these go through the picker,
    # which is the only thing that wants it.
    test "another term narrows while the narrowed set is non-empty" do
      wide = picked("sanderson")
      narrow = picked("sanderson mistborn")

      assert "The Way of Kings" in wide
      assert "Mistborn: The Final Empire" in wide
      assert narrow == ["Mistborn: The Final Empire"]
    end

    test "and widens rather than emptying when nothing matches everything" do
      # `:all` cannot answer this — no record holds "unabridged" — so the
      # box falls back instead of going blank.
      assert hits("sanderson kings unabridged", joiner: :all) == []
      assert ["The Way of Kings" | _also_by_sanderson] = picked("sanderson kings unabridged")
    end

    test "which build/2 cannot express, and says so" do
      assert_raise FunctionClauseError, fn ->
        Query.build("sanderson", joiner: :narrowing)
      end
    end
  end

  describe "stop words" do
    setup do
      insert(:book, title: "The End of All Things")
      insert(:book, title: "End of Watch")
      insert(:book, title: "Don Quixote")
      :ok
    end

    # This is the whole of the second reported bug: every extra common word
    # OR'd in more of the library and dragged the ranking with it.
    test "a stop word alongside real terms changes nothing" do
      assert hits("end of all things") == hits("the end of all things")
      assert top("the end of all things") == "The End of All Things"
    end

    test "but a phrase that is nothing else is still a search for them" do
      # Somebody named Don, or Will. The only case the simple branch's stop
      # words were ever added to serve.
      assert top("don") == "Don Quixote"
    end
  end

  describe "prefixes are of what was typed, not of its stem" do
    setup do
      insert(:person, name: "Martha Wells")
      insert(:book, title: "Red Mars")
      :ok
    end

    test "a stemmed term does not prefix-match unrelated words" do
      # "mars" stems to "mar", and v2 appended `:*` after stemming — so this
      # found Martha, Marlon, Markson, Marin, Martin, Marsters and Maryam.
      hits = hits("mars", joiner: :any, partial: true)

      assert "Red Mars" in hits
      refute "Martha Wells" in hits
    end

    test "while the prefix property itself is untouched" do
      assert top("mar", joiner: :any, partial: true, types: [:person]) == "Martha Wells"
    end
  end

  describe "phrase position" do
    setup do
      # A series that repeats its book's title, which is how the wrong book
      # got to the top: two hits for one fact.
      club = insert(:series, name: "Thursday Murder Club", series_books: [])

      insert(:book,
        title: "The Thursday Murder Club",
        series_books: [%{series_id: club.id, book_number: 1}]
      )

      insert(:book, title: "Murder by Other Means")
      :ok
    end

    test "a name that starts with the phrase outranks one that merely contains it" do
      assert top("murder") == "Murder by Other Means"
    end

    test "a stop word inside the phrase still narrows, though it is not a term" do
      # "by" leaves the tsquery entirely, so this and "murder" are the same
      # search — the phrase tiebreak is the only thing that can tell them
      # apart, and it is the reason typing more feels like it works.
      assert top("murder by") == "Murder by Other Means"
    end

    test "and it cannot widen a result set, only reorder one" do
      refute "The Thursday Murder Club" in hits("murder by other means")
    end
  end

  describe "partial" do
    test "a prefix finds the name it starts" do
      refute top("sander", partial: false) == "Brandon Sanderson"
      assert top("sander", partial: true) == "Brandon Sanderson"
    end

    test "only the last term is opened to a prefix" do
      # "brandon sand" — the first term must still match in full.
      assert top("brandon sand", partial: true) == "Brandon Sanderson"
      refute top("brand sanderson", partial: true) == "Brandon Sanderson"
    end
  end

  describe "an empty phrase" do
    test "shows the first page rather than nothing" do
      assert length(hits("")) > 1
      assert length(hits("   ")) > 1
    end

    # Emphatically NOT the same as an empty box. A phrase the index cannot
    # hold matches nothing; only a box with nothing in it is an invitation to
    # browse. Conflating them meant a phrase the analyzer emptied returned the
    # entire library.
    test "a phrase with nothing searchable in it matches nothing, not everything" do
      assert hits("%") == []
      assert hits("- , [ ]") == []
    end
  end

  describe "types" do
    test "a caller can scope to one kind of record" do
      assert hits("sanderson", joiner: :any, types: [:person]) == ["Brandon Sanderson"]

      book_hits = hits("sanderson", joiner: :any, types: [:book])

      assert "The Way of Kings" in book_hits
      refute "Brandon Sanderson" in book_hits
    end
  end

  describe "both analyses" do
    # A prose analyzer on a catalogue of proper nouns deletes names: English's
    # stop list holds `don` (from "don't"), `will`, `can`, `just` and `now`,
    # so "Don Quixote" indexed as `'quixot'` and a search for Don returned
    # every record in the library.
    #
    # Dropping the stemmer is not the answer either — it is what makes the
    # second pair below work. So both analyses are indexed and both are
    # asked, which is what a real search engine's multi-fields do.
    setup do
      don = insert(:book, title: "Don Quixote")
      rat = insert(:book, title: "King Rat")
      memory = insert(:book, title: "Children of Memory")

      %{don: don, rat: rat, memory: memory}
    end

    test "a name the stemmer would have deleted is findable" do
      assert top("don") == "Don Quixote"
    end

    test "and a stemmed form still is" do
      # Not `top/1`: "The Way of Kings" contains the word "kings" literally
      # and King Rat only reaches it through the stemmer, so the phrase-
      # position tiebreak — rightly — puts the literal match first. What
      # this pins is that the stemmed one is reachable at all.
      assert "King Rat" in hits("kings")
      assert top("memories") == "Children of Memory"
    end

    test "an article the operator typed does not break a title without one" do
      # Neither branch wants it: a stop word alongside real terms is dropped
      # from both, so the article is simply not part of the search.
      assert top("the way of kings") == "The Way of Kings"
    end
  end

  describe "universes" do
    test "a shelf nobody can name a book of is findable by its own name" do
      hits = hits("cosmere")

      assert "The Cosmere" in hits
      assert "The Way of Kings" in hits
      assert "Mistborn: The Final Empire" in hits
    end

    test "and by who writes in it" do
      assert "The Cosmere" in hits("sanderson", joiner: :any, types: [:universe])
    end
  end

  describe "what user search does not show" do
    test "a pen name is indexed, but never a result on its own" do
      # Authors and narrators are records so the credit pickers can ask the
      # index for them. They would be duplicates on a results page — the
      # person is already there, under the same name — so `Ambry.Search`
      # scopes them out.
      assert "Brandon Sanderson" in hits("sanderson", joiner: :any, types: [:author])

      types =
        "sanderson"
        |> Ambry.Search.search()
        |> Enum.map(&(&1.__struct__ |> Module.split() |> List.last()))
        |> Enum.uniq()

      refute "Author" in types
      refute "Narrator" in types
    end
  end

  describe "cross-type results" do
    test "a series surfaces alongside its books" do
      hits = hits("stormlight")

      assert "The Stormlight Archive" in hits
      assert "The Way of Kings" in hits
    end
  end

  defp hits(phrase, opts \\ []) do
    phrase
    |> Query.build(opts)
    |> Ambry.Repo.all()
    |> Enum.map(& &1.primary)
  end

  # What a picker actually returns, by name — the only way to see
  # `:narrowing`, which is a rule about two queries rather than one query.
  defp picked(phrase) do
    phrase |> Ambry.Books.search_books(10) |> Enum.map(& &1.label)
  end

  defp top(phrase, opts \\ []) do
    case hits(phrase, opts) do
      [] -> nil
      [first | _rest] -> first
    end
  end
end
