defmodule Ambry.Inbox.AutoMatchTest do
  use Ambry.DataCase
  use Patch

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

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
      # Matching also asks the matched work for its editions and hydrates the
      # top candidate. Both are real HTTP unless stubbed — and the only reason
      # this suite wasn't already making live calls is that the fake ids
      # happen not to parse.
      patch(Providers, :editions, fn _id, _work_id, _opts -> {:ok, []} end)
      patch(Providers, :book_details, fn _id, _book_id, _opts -> {:error, :not_stubbed} end)
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
    end

    # The library search is a substring ILIKE over one field at a time, so
    # `"#{title} #{author}"` is not a substring of any title and matched
    # nothing — on every item whose tags name an author, which 1b measured at
    # 96% of them. "Is this a book you already have" could not find an answer
    # to offer, which is exactly #1186's bug repeated in the local search.
    test "finds a book already in the library despite the author in the hints" do
      book = insert(:book, title: "Leviathan Wakes")

      %{matches: matches} =
        AutoMatch.match(item(title: "Leviathan Wakes", author: "James S.A. Corey"))

      assert [%{"id" => id}] = matches["work"]["local"]
      assert id == book.id
    end

    # A tag title is rarely the library's title: editions and subtitles get
    # bolted on, and typographic apostrophes are a coin flip between the file
    # and the record.
    test "finds it through an edition suffix, a subtitle and a curly apostrophe" do
      stone = insert(:book, title: "Harry Potter and the Philosopher's Stone")
      lattes = insert(:book, title: "Legends and Lattes")

      %{matches: full_cast} =
        AutoMatch.match(
          item(
            title: "Harry Potter and the Philosopher\u2019s Stone (Full-Cast Edition)",
            author: "J.K. Rowling"
          )
        )

      %{matches: subtitled} =
        AutoMatch.match(item(title: "Legends and Lattes: A Novel of High Fantasy and Low Stakes"))

      assert [%{"id" => stone_id}] = full_cast["work"]["local"]
      assert stone_id == stone.id

      assert [%{"id" => lattes_id}] = subtitled["work"]["local"]
      assert lattes_id == lattes.id
    end

    # Keywords recall far more than the substring search did, and one shared
    # word is not a reason to ask "do you already have this?" — measured on the
    # operator's library, Anne of Green Gables was being offered as a candidate
    # for Leviathan Wakes.
    test "one shared word is not enough to offer a book" do
      insert(:book, title: "Anne of Green Gables")
      wakes = insert(:book, title: "Leviathan Wakes")

      %{matches: matches} =
        AutoMatch.match(item(title: "Leviathan Wakes", author: "James S.A. Corey"))

      assert [%{"id" => id}] = matches["work"]["local"]
      assert id == wakes.id
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

    # Every provider we use reports a book's position in its series
    # (Hardcover's `position`, rreading-glasses' `PositionInSeries`, Audible's
    # `sequence`), and it was being dropped on the floor here — so the inbox
    # asked the operator for a number nobody had to look up.
    test "carries each series' number, not just its name" do
      patch_work_results([
        book("Leviathan Wakes", ["James S.A. Corey"],
          series: [
            %Provider.Series{id: "s1", name: "The Expanse", number: "1"},
            %Provider.Series{id: "s2", name: "The Expanse (Chronological)", number: "2"}
          ]
        )
      ])

      %{matches: matches} = AutoMatch.match(item(title: "Leviathan Wakes"))

      assert [best | _rest] = matches["work"]["candidates"]

      assert best["series"] == [
               %{"name" => "The Expanse", "number" => "1"},
               %{"name" => "The Expanse (Chronological)", "number" => "2"}
             ]
    end

    # Nothing waits on matching, so it is allowed to be thorough: every record
    # about the top work gets its full details fetched, not just the single
    # best one. They all feed the field candidates, so a thin one means the
    # operator can't take the other database's description after all.
    test "fetches full details for every record about the top work" do
      patch_work_results([
        book("Leviathan Wakes", ["James S.A. Corey"]),
        book("Leviathan Wakes", ["James S.A. Corey"])
      ])

      patch(Providers, :book_details, fn _id, _book_id, _opts ->
        {:ok, %Provider.Book{provider: "test", id: "x", description: "fetched"}}
      end)

      %{matches: matches} = AutoMatch.match(item(title: "Leviathan Wakes"))

      assert length(matches["work"]["candidates"]) == 2
      assert Enum.all?(matches["work"]["candidates"], & &1["hydrated"])
      assert Enum.all?(matches["work"]["candidates"], &(&1["description"] == "fetched"))
    end

    test "records the search's fields, not only its flattened string" do
      patch_work_results([book("Neuromancer", ["William Gibson"])])

      %{matches: matches} =
        AutoMatch.match(item(title: "Neuromancer", author: "William Gibson"))

      # "what did you even search for?" is the first question a bad match
      # raises, and the flattened string doesn't answer it — Audible matches
      # `title` against the title alone
      assert matches["work"]["query_fields"] == %{
               "title" => "Neuromancer",
               "author" => "William Gibson"
             }
    end

    # A Book already in the library is a different KIND of answer from a
    # provider record: linking to it creates nothing and inherits its
    # curation. Ranking the two in one list made the form ask one question
    # that was really two.
    test "keeps books already in the library out of the provider records" do
      insert(:book, title: "The Way of Kings")
      patch_work_results([book("The Way of Kings", ["Brandon Sanderson"])])

      %{matches: matches} = AutoMatch.match(item(title: "The Way of Kings"))

      assert [local] = matches["work"]["local"]
      assert local["title"] == "The Way of Kings"
      assert Enum.all?(matches["work"]["candidates"], &(&1["source"] != "local"))
    end

    test "reports low confidence when two different books are equally good" do
      patch_work_results([
        book("The Silent Patient", ["Alex Michaelides"]),
        book("The Silent Patients", ["Alexa Michaelides"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "The Silent Patient"))

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["score"] > 0.9
      # a strong match with an equally strong runner-up is exactly what a
      # human should look at
      assert matches["work"]["confidence"] < 0.6
    end

    # Two providers returning the SAME work is corroboration, not conflict.
    # Treating it as a tie dropped perfect double hits to 0.5 confidence and
    # sent obviously-correct matches back to the operator to adjudicate.
    # Records are NOT fused when two databases return the same thing — that's
    # the normal case, and each knows things the other doesn't. But for
    # *scoring* they're one answer, or the runner-up penalty reads the
    # best-corroborated match in the library as the most doubtful one.
    test "two providers agreeing is corroboration, not a tie" do
      patch_work_results([
        book("The Silent Patient", ["Alex Michaelides"]),
        book("The Silent Patient", ["Alex Michaelides"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "The Silent Patient"))

      # both records survive, so both can propose values
      assert length(matches["work"]["candidates"]) == 2
      assert matches["work"]["confidence"] > 0.9
    end

    test "records what each provider was asked and what it said" do
      patch_work_results([book("The Silent Patient", ["Alex Michaelides"])])

      %{matches: matches} = AutoMatch.match(item(title: "The Silent Patient"))

      assert [outcome | _rest] = matches["work"]["providers"]
      assert outcome["status"] == "ok"
      assert outcome["count"] >= 1
    end

    # Jaro distance rewards shared substrings and cannot see *extra* content,
    # so companion works scored ~0.7 against the book they discuss and sat
    # near the top of the candidate list looking plausible.
    test "companion works are pushed well below the real thing" do
      patch_work_results([
        book("Neuromancer", ["William Gibson"]),
        book("A Study Guide for William Gibson's Neuromancer", ["Gale"]),
        book("William Gibson's Neuromancer, the Graphic Novel", ["Tom De Haven"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "Neuromancer", author: "William Gibson"))

      [best | rest] = matches["work"]["candidates"]

      assert best["title"] == "Neuromancer"
      assert Enum.all?(rest, &(&1["score"] < 0.4))
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

      assert [%{"title" => "The Way of Kings"}] = matches["work"]["local"]
      assert [outcome | _rest] = matches["work"]["providers"]
      assert outcome["status"] == "failed"
    end

    # Audible's catalog API is a storefront, not a bibliography: when rights
    # lapse the title vanishes from search AND from direct ASIN lookup, with
    # no record it ever existed. A work-level provider that keeps editions
    # still has it — so the matched work's own editions are a third key.
    test "the matched work's editions become recording candidates" do
      patch_work_results([book("Neuromancer", ["William Gibson"])])

      # Hardcover is the provider that keeps editions, but it needs a token and
      # so is unavailable in test — the capability is what matters here, not
      # which provider happens to carry it.
      entries = Map.new(Registry.all(), &{&1.id, &1})

      patch(Registry, :fetch, fn id ->
        case Map.fetch(entries, id) do
          {:ok, entry} -> {:ok, %{entry | capabilities: [:editions | entry.capabilities]}}
          :error -> {:error, :unknown_provider}
        end
      end)

      patch(Providers, :editions, fn _id, _work_id, _opts ->
        {:ok,
         [
           %Provider.Book{
             provider: "hardcover",
             id: "e1",
             title: "Neuromancer",
             publisher: "Books on Tape",
             narrators: [%Provider.Contributor{name: "Arthur Addison", role: "narrator"}]
           }
         ]}
      end)

      %{matches: matches} =
        AutoMatch.match(item(title: "Neuromancer", author: "William Gibson"))

      titles = Enum.map(matches["recording"]["candidates"], & &1["narrators"])
      assert [["Arthur Addison"]] == titles

      assert Enum.any?(matches["recording"]["providers"], &(&1["id"] =~ ":editions"))
    end

    # Two audiobooks of one work share a title and an author; they are not the
    # same thing. Keying only on those collapsed the 1984 Books on Tape and
    # 2011 Penguin editions of Neuromancer into a single candidate.
    test "two recordings of one work are not merged" do
      patch_recording_results([
        book("Neuromancer", ["William Gibson"], narrators: ["Robertson Dean"], asin: "A1"),
        book("Neuromancer", ["William Gibson"], narrators: ["Arthur Addison"], asin: "A2")
      ])

      %{matches: matches} = AutoMatch.match(item(title: "Neuromancer"))

      assert length(matches["recording"]["candidates"]) == 2
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
      authors: Enum.map(authors, &%Provider.Contributor{name: &1, role: "author"}),
      narrators:
        Enum.map(opts[:narrators] || [], &%Provider.Contributor{name: &1, role: "narrator"}),
      series: opts[:series] || []
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
