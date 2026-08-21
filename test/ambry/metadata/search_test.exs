defmodule Ambry.Metadata.SearchTest do
  @moduledoc """
  The chapters fan-out: chapter lists come off the registry's `:chapters`
  capability, not off a hardcoded provider id — the #1226 audit's last
  outstanding item.
  """
  use Ambry.DataCase, async: false
  use Patch

  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Search

  describe "chapters/2" do
    test "asks every chapter-capable provider on the registry, by ASIN" do
      patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B01", _config ->
        {:ok,
         %Provider.Chapters{
           provider: "audnexus",
           asin: "B01",
           chapters: [%Provider.Chapter{title: "One", start_offset_ms: 0}]
         }}
      end)

      assert {[{entry, chapters}], [outcome]} = Search.chapters("B01")
      assert entry.id == "audnexus"
      assert [%{title: "One"}] = chapters.chapters
      assert %{"id" => "audnexus", "status" => "ok", "count" => 1} = outcome
    end

    # "Found nothing" and "was unreachable" have to be told apart afterwards.
    @tag :capture_log
    test "reports a provider that failed instead of hiding it" do
      patch(Ambry.Metadata.Providers.Audnexus, :chapters, fn "B01", _config ->
        {:error, :timeout}
      end)

      assert {[], [outcome]} = Search.chapters("B01")
      assert %{"id" => "audnexus", "status" => "failed"} = outcome
    end
  end

  describe "books/2" do
    # A provider that is several sources behind one name — Audible's regional
    # catalogs — can answer by halves, and the answer is usable and
    # incomplete. Reported as a failure *carrying a count*, because everything
    # that reads outcomes asks one question of them: is there something a
    # retry could still get?
    @tag :capture_log
    test "a provider that answered by halves keeps its records and its retry" do
      patch(Ambry.Metadata.Providers.Audible, :search_books, fn _query, _config ->
        {:partial, [%Provider.Book{provider: "audible", id: "US1", title: "A Book"}],
         "uk: HTTP 429"}
      end)

      {found, outcomes} =
        Search.books(%Provider.Query{title: "A Book"}, level: :recording, refresh: true)

      assert [{_entry, [%{id: "US1"}]}] = Enum.filter(found, fn {e, _b} -> e.id == "audible" end)

      assert %{"status" => "failed", "count" => 1, "partial" => true, "reason" => reason} =
               Enum.find(outcomes, &(&1["id"] == "audible"))

      assert reason =~ "uk"

      # which is what sends the matching job round again for the rest
      assert Ambry.Metadata.Outcome.failed?(Enum.find(outcomes, &(&1["id"] == "audible")))
    end
  end
end
