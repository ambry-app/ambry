defmodule Ambry.Inbox.AutoMatchTest do
  use Ambry.DataCase
  use Patch

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers

  describe "hints/1" do
    test "prefers tags over the release name" do
      item = %InboxItem{
        path: "/downloads/Somebody Else - Some Other Book",
        tags: %{"book_title" => "The Way of Kings", "authors" => ["Brandon Sanderson"]}
      }

      assert %{title: "The Way of Kings", author: "Brandon Sanderson"} = AutoMatch.hints(item)
    end

    test "falls back to the release name when tags are empty" do
      item = %InboxItem{path: "/downloads/Cory Doctorow - The Bezzle [m4b]", tags: %{}}

      assert %{title: "The Bezzle", author: "Cory Doctorow"} = AutoMatch.hints(item)
    end

    test "takes an ASIN from wherever it appears" do
      assert %{asin: "B0D6PCZ98M"} =
               AutoMatch.hints(%InboxItem{
                 path: "/d/Sunrise on the Reaping [B0D6PCZ98M]",
                 tags: %{}
               })

      assert %{asin: "B003ZWFO7E"} =
               AutoMatch.hints(%InboxItem{path: "/d/Whatever", tags: %{"asin" => "B003ZWFO7E"}})
    end
  end

  describe "match/1" do
    setup do
      patch(Providers, :search_books, fn _id, _query, _opts -> {:ok, []} end)
      :ok
    end

    test "ranks a good provider hit above a poor one" do
      patch_work_results([
        book("Some Entirely Different Book", ["Nobody"]),
        book("The Way of Kings", ["Brandon Sanderson"])
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "The Way of Kings", author: "Brandon Sanderson"))

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["title"] == "The Way of Kings"
      assert best["score"] > 0.9
      assert matches["work"]["selected"]["source"] =~ "provider:"
    end

    test "keeps every candidate, not just the winner" do
      patch_work_results([
        book("The Way of Kings", ["Brandon Sanderson"]),
        book("The Way of Kings Prime", ["Brandon Sanderson"]),
        book("Way of the Kings", ["Someone Else"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "The Way of Kings"))

      assert length(matches["work"]["candidates"]) == 3
    end

    test "an ASIN match beats everything on similarity alone" do
      patch_recording_results([
        book("A Much Closer Title Match", ["Brandon Sanderson"], asin: "B000000000"),
        book("Kings, The Way Of (Dramatized)", ["Brandon Sanderson"], asin: "B003ZWFO7E")
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "The Way of Kings", asin: "B003ZWFO7E"))

      assert [best | _rest] = matches["recording"]["candidates"]
      assert best["asin"] == "B003ZWFO7E"
      assert best["score"] == 1.0
      assert matches["recording"]["query"] == "B003ZWFO7E"
    end

    test "ranks a book already in the library first" do
      insert(:book, title: "The Way of Kings")
      patch_work_results([book("The Way of Kings", ["Brandon Sanderson"])])

      %{matches: matches} = AutoMatch.match(item(title: "The Way of Kings"))

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["source"] == "local"
    end

    test "reports low confidence when two candidates are equally good" do
      patch_work_results([
        book("The Silent Patient", ["Alex Michaelides"]),
        book("The Silent Patient", ["Alex Michaelides"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "The Silent Patient"))

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["score"] > 0.9
      # a strong match with an equally strong runner-up is exactly what a
      # human should look at
      assert matches["work"]["confidence"] < 0.6
    end

    test "is confident when the winner stands alone" do
      patch_work_results([
        book("The Silent Patient", ["Alex Michaelides"]),
        book("Something Unrelated Entirely", ["Nobody At All"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "The Silent Patient"))

      assert matches["work"]["confidence"] > 0.5
    end

    @tag :capture_log
    test "a failing provider costs its results, not the match" do
      patch(Providers, :search_books, fn _id, _query, _opts -> {:error, :rate_limited} end)

      insert(:book, title: "The Way of Kings")

      %{matches: matches} = AutoMatch.match(item(title: "The Way of Kings"))

      assert [%{"source" => "local"} | _rest] = matches["work"]["candidates"]
    end

    test "an item with nothing to go on proposes nothing rather than guessing" do
      %{matches: matches} = AutoMatch.match(%InboxItem{path: "/downloads/", tags: %{}})

      assert matches["work"]["candidates"] == []
      assert matches["work"]["confidence"] == 0.0
      assert matches["work"]["selected"] == nil
    end
  end

  defp item(opts) do
    %InboxItem{
      path: "/downloads/#{Keyword.get(opts, :title, "Unknown")}",
      tags:
        %{
          "book_title" => opts[:title],
          "authors" => (opts[:author] && [opts[:author]]) || [],
          "asin" => opts[:asin]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

  defp book(title, authors, opts \\ []) do
    %Provider.Book{
      provider: "test",
      id: "id-#{:erlang.phash2(title)}",
      title: title,
      asin: opts[:asin],
      authors: Enum.map(authors, &%Provider.Contributor{name: &1, role: "author"})
    }
  end

  # The registry is driven by real provider modules, so tests patch the
  # facade every search goes through instead of inventing providers.
  defp patch_work_results(books) do
    patch(Providers, :search_books, fn id, _query, _opts ->
      if work_provider?(id), do: {:ok, books}, else: {:ok, []}
    end)
  end

  defp patch_recording_results(books) do
    patch(Providers, :search_books, fn id, _query, _opts ->
      if work_provider?(id), do: {:ok, []}, else: {:ok, books}
    end)
  end

  defp work_provider?(id), do: id in ["rreading_glasses", "hardcover"]
end
