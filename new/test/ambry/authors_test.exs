defmodule Ambry.AuthorsTest do
  use Ambry.DataCase

  alias Ambry.Authors

  describe "search/1" do
    test "searches for author by name" do
      [%{name: name} | _] = insert_list(3, :author)

      list = Authors.search(name)

      assert [{_, %Authors.Author{}}] = list
    end
  end

  describe "search/2" do
    test "accepts a limit" do
      insert_list(3, :author, name: "Foo Bar Baz")

      list = Authors.search("Foo", 2)

      assert [
               {_, %Authors.Author{}},
               {_, %Authors.Author{}}
             ] = list
    end
  end

  describe "for_select/0" do
    test "returns all author names and ids only" do
      insert_list(3, :author)

      list = Authors.for_select()

      assert [
               {_, _},
               {_, _},
               {_, _}
             ] = list
    end
  end
end
