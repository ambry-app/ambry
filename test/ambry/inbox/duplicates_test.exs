defmodule Ambry.Inbox.DuplicatesTest do
  use Ambry.DataCase

  alias Ambry.Inbox.Duplicates

  describe "check/0" do
    test "a library with nothing in it twice reports nothing" do
      insert(:person, name: "Brandon Sanderson")
      insert(:person, name: "Becky Chambers")
      insert(:book, title: "Evershore")
      insert(:series, name: "Skyward Flight")

      assert Duplicates.check() == []
      assert Duplicates.count() == 0
    end

    # The pair production actually had, spelled the way the two spellings
    # that most often produce one arrive: an accent from one provider and
    # none from another.
    test "finds two people of one name, and says what points at each" do
      kept = insert(:person, name: "Patricia Rodríguez")
      spare = insert(:person, name: "Patricia Rodriguez")
      insert(:narrator, name: "Patricia Rodríguez", person: kept)

      assert [group] = for(g <- Duplicates.check(), g.kind == :person, do: g)
      assert [first, second] = group.records

      assert first.id == kept.id
      assert first.uses == %{authors: 0, narrators: 1}

      assert second.id == spare.id
      assert second.uses == %{authors: 0, narrators: 0}
    end

    test "a leading article does not make a different book" do
      one = insert(:book, title: "The Princess Bride")
      two = insert(:book, title: "Princess Bride")
      insert(:media, book: one)

      assert [group] = for(g <- Duplicates.check(), g.kind == :book, do: g)
      assert Enum.map(group.records, & &1.id) == Enum.sort([one.id, two.id])
      assert [%{uses: %{audiobooks: 1}}, %{uses: %{audiobooks: 0}}] = group.records
    end

    # `same_series?/2` is a predicate rather than a key, so this is the case
    # that would fall through a plain group-by: neither name is a prefix or a
    # normalisation of the other, they simply mean the same shelf.
    test "a filler word does not make a different series" do
      saga = insert(:series, name: "The Mistborn Saga")
      trilogy = insert(:series, name: "Mistborn Trilogy")

      assert [group] = for(g <- Duplicates.check(), g.kind == :series, do: g)
      assert Enum.map(group.records, & &1.id) == Enum.sort([saga.id, trilogy.id])
    end

    test "three spellings of one name are one set, not three pairs" do
      for name <- ["J.K. Rowling", "J. K. Rowling", "JK Rowling"] do
        insert(:narrator, name: name, person: insert(:person, name: name))
      end

      assert [group] = for(g <- Duplicates.check(), g.kind == :narrator, do: g)
      assert length(group.records) == 3
    end
  end

  describe "scanned/0" do
    # A report of nothing has to be able to say what nothing covers, or it
    # reads the same as a report that never ran.
    test "counts what the check looked at" do
      insert(:person, name: "Becky Chambers")
      insert(:book, title: "A Psalm for the Wild-Built")

      assert %{people: 1, books: 1, authors: 0, narrators: 0, series: 0} = Duplicates.scanned()
    end
  end
end
