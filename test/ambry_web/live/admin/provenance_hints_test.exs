defmodule AmbryWeb.Admin.ProvenanceHintsTest do
  use ExUnit.Case, async: true

  alias AmbryWeb.Admin.ProvenanceHints

  describe "from_import/2" do
    test "date structs are scalar hint values (associations stay excluded)" do
      # %Date{} is a map — the association filter must not swallow it, or
      # accepted published dates save as manual edits (v1.9.0 punch list)
      params = %{
        "published" => ~D[2011-06-15],
        "published_format" => "full",
        "book_authors" => [%{"author_id" => 1}]
      }

      hints = ProvenanceHints.from_import(params, "provider:hardcover")

      assert %{value: "2011-06-15", watch: "published"} = hints["published"]
      assert %{value: "full"} = hints["published_format"]
      refute Map.has_key?(hints, "book_authors")

      assert ProvenanceHints.sources(hints) == %{
               "published" => "provider:hardcover",
               "published_format" => "provider:hardcover"
             }
    end
  end

  describe "prune/2" do
    test "a date hint survives the form echoing the rendered value and dies on edit" do
      hints = ProvenanceHints.from_import(%{"published" => ~D[2011-06-15]}, "provider:x")

      assert ProvenanceHints.prune(hints, %{"published" => "2011-06-15"}) == hints
      assert ProvenanceHints.prune(hints, %{"published" => "2012-01-01"}) == %{}
    end
  end
end
