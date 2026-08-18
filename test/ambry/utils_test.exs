defmodule Ambry.UtilsTest do
  @moduledoc """
  The wordings shared between the contexts and the web layer, which is what
  keeps a row and a picker option from crediting the same recording two
  different ways.
  """
  use ExUnit.Case, async: true

  doctest Ambry.Utils, only: [name_credit: 1, series_credit: 1, humanize_bytes: 1]

  describe "name_credit/1" do
    test "says nothing when there is nobody" do
      assert Ambry.Utils.name_credit([]) == nil
      assert Ambry.Utils.name_credit(nil) == nil
    end

    # "and 1 others" is the tell of a count pasted onto a plural.
    test "agrees with its noun" do
      assert Ambry.Utils.name_credit([%{name: "A"}, %{name: "B"}]) == "A and 1 other"

      assert Ambry.Utils.name_credit([%{name: "A"}, %{name: "B"}, %{name: "C"}]) ==
               "A and 2 others"
    end
  end

  describe "series_credit/1" do
    test "joins several with commas" do
      series = [%{name: "Mistborn", number: 2}, %{name: "The Cosmere", number: 4}]

      assert Ambry.Utils.series_credit(series) == "Mistborn #2, The Cosmere #4"
    end

    test "says nothing when a record is in no series" do
      assert Ambry.Utils.series_credit([]) == nil
      assert Ambry.Utils.series_credit(nil) == nil
    end
  end
end
