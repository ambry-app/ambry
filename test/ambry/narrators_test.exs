defmodule Ambry.NarratorsTest do
  use Ambry.DataCase

  alias Ambry.Narrators

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
