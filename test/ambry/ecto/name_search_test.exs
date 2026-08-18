defmodule Ambry.Ecto.NameSearchTest do
  @moduledoc """
  The rule the three remaining name pickers narrow their options by.

  Exercised through `People.search_authors/2`, which is now the thinnest
  caller — what is under test is the shared `narrow/4`, not the authors
  table. The series picker used to play that role and has moved to the search
  index; the pickers left here are the ones whose subject is not a record.
  See `Ambry.Ecto.NameSearch` for which and why.
  """
  use Ambry.DataCase

  alias Ambry.People

  defp names(phrase, limit \\ 10) do
    phrase |> People.search_authors(limit) |> Enum.map(& &1.label)
  end

  describe "narrow/4" do
    test "an empty phrase is the first page, not nothing" do
      insert(:author, name: "Alpha")
      insert(:author, name: "Beta")

      assert names("") == ["Alpha", "Beta"]
      assert names("   ", 1) == ["Alpha"]
    end

    test "matches anywhere in the name, case-blind" do
      insert(:author, name: "Brandon Sanderson")

      assert names("SANDERSON") == ["Brandon Sanderson"]
    end

    # A prefix is the stronger signal, and alphabetical order would bury it:
    # typing "sander" wants the name that starts with it first.
    test "a prefix outranks a substring" do
      insert(:author, name: "Brandon Sanderson")
      insert(:author, name: "Sanderson Reed")

      assert names("sanderson") == ["Sanderson Reed", "Brandon Sanderson"]
    end

    # `unaccent` is the SQL twin of the NFD fold the in-memory filter did.
    # Without it the library's spelling and a file's are two records.
    test "folds accents both ways" do
      insert(:author, name: "Patricia Rodríguez")

      assert names("rodriguez") == ["Patricia Rodríguez"]
      assert names("rodríguez") == ["Patricia Rodríguez"]
    end

    # A name is operator input, and `%` and `_` are legal characters in one.
    test "wildcards are characters, not patterns" do
      insert(:author, name: "Mistborn")

      assert names("%") == []
      assert names("_istborn") == []
      assert names("Mistborn") == ["Mistborn"]
    end

    test "matches a name that really does hold a wildcard" do
      insert(:author, name: "100% Wolf")

      assert names("100%") == ["100% Wolf"]
    end

    test "stops at the limit" do
      insert_list(4, :author)

      assert length(names("", 2)) == 2
    end
  end
end
