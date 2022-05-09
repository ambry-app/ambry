defmodule Ambry.NarratorsTest do
  use Ambry.DataCase

  alias Ambry.Narrators

  describe "search/1" do
    test "searches for narrator by name" do
      [%{name: name} | _] = insert_list(3, :narrator)

      list = Narrators.search(name)

      assert [{_, %Narrators.Narrator{}}] = list
    end
  end

  describe "search/2" do
    test "accepts a limit" do
      insert_list(3, :narrator, name: "Foo Bar Baz")

      list = Narrators.search("Foo", 2)

      assert [
               {_, %Narrators.Narrator{}},
               {_, %Narrators.Narrator{}}
             ] = list
    end
  end

  describe "for_select/0" do
    test "returns all narrator names and ids only" do
      insert_list(3, :narrator)

      list = Narrators.for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
