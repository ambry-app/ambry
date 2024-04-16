defmodule Ambry.People.PersonName.TypeTest do
  use Ambry.DataCase

  alias Ambry.People.PersonName

  describe "type/0" do
    test "returns `:person_name`" do
      assert :person_name = PersonName.Type.type()
    end
  end

  describe "cast/1" do
    test "accepts a PersonName struct" do
      assert {:ok, %PersonName{}} = PersonName.Type.cast(%PersonName{})
    end

    test "error for anything else" do
      assert :error = PersonName.Type.cast("foo")
    end
  end

  describe "load/1" do
    test "loads a tuple from the database into a PersonName struct" do
      assert {:ok, %PersonName{name: "Foo", person_name: "Bar"}} =
               PersonName.Type.load({"Foo", "Bar"})
    end
  end

  describe "dump/1" do
    test "dumps a PersonName struct to the database as a tuple" do
      assert {:ok, {"Foo", "Bar"}} =
               PersonName.Type.dump(%PersonName{name: "Foo", person_name: "Bar"})
    end

    test "error for anything else" do
      assert :error = PersonName.Type.dump("foo")
    end
  end
end
