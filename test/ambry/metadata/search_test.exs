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
end
