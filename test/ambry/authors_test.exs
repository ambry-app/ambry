defmodule Ambry.AuthorsTest do
  use Ambry.DataCase

  alias Ambry.Authors

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
