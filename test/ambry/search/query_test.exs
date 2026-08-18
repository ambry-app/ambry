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

    # The British title on the book, the American one on the recording. Both
    # have to find it.
    philosophers_stone = insert(:book, title: "Harry Potter and the Philosopher's Stone")

    insert(:media,
      book: philosophers_stone,
      title: "Harry Potter and the Sorcerer's Stone"
    )

    %{
      way_of_kings: way_of_kings,
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

    test "a phrase of nothing but stop words does the same" do
      assert length(hits("the of and")) > 1
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

  defp top(phrase, opts \\ []) do
    case hits(phrase, opts) do
      [] -> nil
      [first | _rest] -> first
    end
  end
end
