defmodule Ambry.Ecto.NameSearchTest do
  @moduledoc """
  The one rule every picker in the admin narrows its options by.

  Exercised through `Books.search_series/2`, which is the thinnest caller —
  what is under test is the shared `narrow/4`, not the series table.
  """
  use Ambry.DataCase

  alias Ambry.Books

  describe "narrow/4" do
    test "an empty phrase is the first page, not nothing" do
      insert(:series, name: "Alpha")
      insert(:series, name: "Beta")

      assert [{"Alpha", _}, {"Beta", _}] = Books.search_series("", 10)
      assert [{"Alpha", _}] = Books.search_series("   ", 1)
    end

    test "matches anywhere in the name, case-blind" do
      insert(:series, name: "The Stormlight Archive")

      assert [{"The Stormlight Archive", _}] = Books.search_series("STORMLIGHT", 10)
    end

    # A prefix is the stronger signal, and alphabetical order would bury it:
    # typing "storm" wants the series that starts with it first.
    test "a prefix outranks a substring" do
      insert(:series, name: "The Stormlight Archive")
      insert(:series, name: "Stormlight Shorts")

      assert [{"Stormlight Shorts", _}, {"The Stormlight Archive", _}] =
               Books.search_series("stormlight", 10)
    end

    # `unaccent` is the SQL twin of the NFD fold the in-memory filter did.
    # Without it the library's spelling and a file's are two records.
    test "folds accents both ways" do
      insert(:series, name: "Los Niños")

      assert [{"Los Niños", _}] = Books.search_series("ninos", 10)
      assert [{"Los Niños", _}] = Books.search_series("niños", 10)
    end

    # A name is operator input, and `%` and `_` are legal characters in one.
    test "wildcards are characters, not patterns" do
      insert(:series, name: "Mistborn")

      assert Books.search_series("%", 10) == []
      assert Books.search_series("_istborn", 10) == []
      assert [{"Mistborn", _}] = Books.search_series("Mistborn", 10)
    end

    test "matches a name that really does hold a wildcard" do
      insert(:series, name: "100% Wolf")

      assert [{"100% Wolf", _}] = Books.search_series("100%", 10)
    end

    test "stops at the limit" do
      insert_list(4, :series)

      assert length(Books.search_series("", 2)) == 2
    end
  end
end
