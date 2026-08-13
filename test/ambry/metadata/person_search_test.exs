defmodule Ambry.Metadata.PersonSearchTest do
  @moduledoc """
  Gathering everything every provider knows about a human — and, when one of
  them couldn't be reached, saying so.

  A person search is two calls deep: a name search, then a details call per
  plausible hit, which is where the biography and the headshots live. The
  details call had no way to report failure, and the consequence was worse
  than a thin result — a hit with no photo and no bio is dropped from the
  grid, so a rate-limited details call **deleted the person** while the
  search still reported `ok`. Measured on a cold scan of 353 releases, the
  shared rreading-glasses instance 429'd about 6% of requests; person calls
  were 84% of the traffic.
  """
  use Ambry.DataCase, async: false
  use Patch

  alias Ambry.Metadata.PersonSearch
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  defp entry, do: %Registry.Entry{id: "wikidata", display_name: "Wikidata"}

  defp summary(id \\ "Q1"),
    do: %Provider.Author{provider: "wikidata", id: id, name: "Brandon Sanderson"}

  describe "matches_with_outcome/3" do
    test "reports the search and nothing else when every call answered" do
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, [summary()]} end)

      patch(Providers, :author_details, fn _id, id, _opts ->
        {:ok, %Provider.Author{provider: "wikidata", id: id, description: "Writes fantasy."}}
      end)

      assert {[match], [outcome]} =
               PersonSearch.matches_with_outcome(entry(), "Brandon Sanderson")

      assert match.description == "Writes fantasy."
      assert %{"id" => "wikidata", "status" => "ok", "count" => 1} = outcome
    end

    @tag :capture_log
    test "a search that couldn't be reached is one failed outcome" do
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:error, :rate_limited} end)

      assert {[], [outcome]} = PersonSearch.matches_with_outcome(entry(), "Brandon Sanderson")
      assert %{"id" => "wikidata", "status" => "failed"} = outcome
    end

    # The one that used to vanish. The search says `ok` — it did find her —
    # and the details call that would have given her a face was rate-limited,
    # so she is dropped from the grid. Without the second outcome, nothing
    # anywhere records that a human the file credits went missing.
    test "a details call that couldn't be reached is reported under its own id" do
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, [summary()]} end)
      patch(Providers, :author_details, fn _id, _author_id, _opts -> {:error, :rate_limited} end)

      assert {matches, outcomes} = PersonSearch.matches_with_outcome(entry(), "Brandon Sanderson")

      assert matches == []
      assert %{"status" => "ok", "count" => 0} = Enum.find(outcomes, &(&1["id"] == "wikidata"))

      assert %{"status" => "failed", "reason" => reason} =
               Enum.find(outcomes, &(&1["id"] == "wikidata:details"))

      assert reason =~ "rate_limited"
    end

    # A provider that simply knows nothing more about somebody is not a
    # failure, and must not be reported as one — otherwise every scan would
    # retry forever against a provider that is behaving perfectly.
    test "a provider with no details to give is not a failure" do
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, [summary()]} end)

      patch(Providers, :author_details, fn _id, _author_id, _opts ->
        {:ok, %Provider.Author{provider: "wikidata", id: "Q1", description: "Known."}}
      end)

      assert {[_match], [%{"id" => "wikidata"}]} =
               PersonSearch.matches_with_outcome(entry(), "Brandon Sanderson")
    end

    # One chip per provider however many hits it returned: three hits and one
    # rate limit is still "Wikidata details: couldn't be reached", not three
    # of them.
    test "several failed hits collapse to one outcome" do
      patch(Providers, :search_authors, fn _id, _query, _opts ->
        {:ok, [summary("Q1"), summary("Q2"), summary("Q3")]}
      end)

      patch(Providers, :author_details, fn _id, _author_id, _opts -> {:error, :rate_limited} end)

      assert {[], outcomes} = PersonSearch.matches_with_outcome(entry(), "Brandon Sanderson")
      assert length(outcomes) == 2
    end
  end
end
