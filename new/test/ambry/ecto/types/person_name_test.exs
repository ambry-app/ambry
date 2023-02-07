defmodule Ambry.Ecto.Types.PersonNameTest do
  use Ambry.DataCase

  alias Ambry.Ecto.Types.PersonName, as: PersonNameType
  alias Ambry.People.PersonName

  describe "type/0" do
    test "returns `:person_name`" do
      assert :person_name = PersonNameType.type()
    end
  end

  describe "cast/1" do
    test "accepts a PersonName struct" do
      assert {:ok, %PersonName{}} = PersonNameType.cast(%PersonName{})
    end

    test "error for anything else" do
      assert :error = PersonNameType.cast("foo")
    end
  end

  describe "load/1" do
    test "loads a tuple from the database into a PersonName struct" do
      assert {:ok, %PersonName{name: "Foo", person_name: "Bar"}} =
               PersonNameType.load({"Foo", "Bar"})
    end
  end

  describe "dump/1" do
    test "dumps a PersonName struct to the database as a tuple" do
      assert {:ok, {"Foo", "Bar"}} =
               PersonNameType.dump(%PersonName{name: "Foo", person_name: "Bar"})
    end

    test "error for anything else" do
      assert :error = PersonNameType.dump("foo")
    end
  end
end
