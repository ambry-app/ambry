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

    # The operator's Children of Time is tagged "Children of Time
    # (Unabridged)", and that parenthetical measurably worsens the provider
    # search — without failing it, so the zero-result plainer-title retry
    # never rescued it. The verbatim tag still reaches the form as a chip;
    # only the question is cleaned.
    test "strips release junk from the tag title" do
      item = %InboxItem{
        path: "/downloads/Adrian Tchaikovsky - Children of Time (m4b)",
        tags: %{"book_title" => "Children of Time (Unabridged)"}
      }

      assert %{title: "Children of Time"} = AutoMatch.hints(item)
    end

    test "a tag title that is nothing but junk falls back to the release name" do
      item = %InboxItem{
        path: "/downloads/Cory Doctorow - The Bezzle [m4b]",
        tags: %{"book_title" => "(Unabridged)"}
      }

      assert %{title: "The Bezzle"} = AutoMatch.hints(item)
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
      # The people level asks every person-capable provider about every
      # credited human, which is real HTTP unless stubbed — and unlike the
      # book calls there is no fake id to save us, because a person is
      # searched by name.
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, []} end)
      patch(Providers, :author_details, fn _id, _author_id, _opts -> {:error, :not_stubbed} end)
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

    # Jaro gives ~0.5 to entirely unrelated titles and the author match adds
    # a quarter-share on top — so once the library held one William Gibson,
    # Pattern Recognition offered Neuromancer as "a book you already have" at
    # 0.68, re-opening the identity question on every import by an author
    # already on the shelf.
    test "a same-author book with an unrelated title is not offered" do
      insert(:book,
        title: "Neuromancer",
        book_authors: [
          build(:book_author,
            author: build(:author, name: "William Gibson", person: build(:person))
          )
        ]
      )

      %{matches: matches} =
        AutoMatch.match(item(title: "Pattern Recognition", author: "William Gibson"))

      assert matches["work"]["local"] == []
    end

    # One word of a title is not evidence of identity: "Elysium Fire" was
    # offered for The Consuming Fire on the strength of "fire". A one-word
    # title fully present still counts — Wool must stay findable from
    # "01 Wool".
    test "a single shared title word is not evidence of identity" do
      insert(:book, title: "Elysium Fire")
      wool = insert(:book, title: "Wool")

      %{matches: fire} =
        AutoMatch.match(
          item(title: "The Consuming Fire: The Interdependency, Book 2", author: "John Scalzi")
        )

      %{matches: wool_match} = AutoMatch.match(item(title: "Wool", author: "Hugh Howey"))

      assert fire["work"]["local"] == []
      assert [%{"id" => id}] = wool_match["work"]["local"]
      assert id == wool.id
    end

    # Same-series siblings share the series name by construction, so The
    # Collapsing Empire was offered as "a book you already have" for The
    # Consuming Fire. A series name is only evidence when the file's label IS
    # the series — "Wayfarers, Book 1" carries no title of its own, so there
    # the series is the only road to the book.
    test "a same-series sibling is not offered through the series name" do
      insert(:book,
        title: "The Collapsing Empire",
        series_books: [
          build(:series_book,
            book_number: 1,
            series: build(:series, name: "The Interdependency")
          )
        ]
      )

      wayfarer =
        insert(:book,
          title: "The Long Way to a Small, Angry Planet",
          book_authors: [
            build(:book_author,
              author: build(:author, name: "Becky Chambers", person: build(:person))
            )
          ],
          series_books: [
            build(:series_book, book_number: 1, series: build(:series, name: "Wayfarers"))
          ]
        )

      %{matches: fire} =
        AutoMatch.match(
          item(title: "The Consuming Fire The Interdependency, Book 2", author: "John Scalzi")
        )

      %{matches: label} =
        AutoMatch.match(item(title: "Wayfarers, Book 1", author: "Becky Chambers"))

      assert fire["work"]["local"] == []
      assert [%{"id" => id}] = label["work"]["local"]
      assert id == wayfarer.id
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

    # Series books share most of their words by construction, so a same-author
    # sibling sat all but the same gap behind an exact match as the Silent
    # Patients near-tie — and dragged a certain, doubly-corroborated match
    # under the doubt bar. Measured on the operator's Children of Time.
    test "a catalogue sibling is not doubt when the best is exact" do
      patch_work_results([
        book("Children of Time", ["Adrian Tchaikovsky"]),
        book("Children of Strife", ["Adrian Tchaikovsky"]),
        book("Children of Memory", ["Adrian Tchaikovsky"])
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "Children of Time", author: "Adrian Tchaikovsky"))

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["title"] == "Children of Time"
      assert matches["work"]["confidence"] > 0.8
    end

    # The discount only applies when the best decisively answered the query.
    # When nothing matched well, a close runner-up is genuine ambiguity no
    # matter how different its title is.
    test "distinct titles still doubt each other when nothing matched well" do
      patch_work_results([
        book("Children of Time", ["Adrian Tchaikovsky"]),
        book("Children of Ruin", ["Adrian Tchaikovsky"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "Children of the Fleet"))

      assert matches["work"]["confidence"] < 0.65
    end

    # The catalogue writes the title out in full and the file's tags carry the
    # bare one. Every subtitle word counted as content the query didn't ask
    # for, and the length penalty scored the right book like a study guide —
    # 0.316, measured on the operator's As You Wish.
    test "a catalogue subtitle is not junk when its head is the queried title" do
      patch_work_results([
        book(
          "As You Wish: Inconceivable Tales from the Making of The Princess Bride",
          ["Cary Elwes"]
        )
      ])

      %{matches: matches} = AutoMatch.match(item(title: "As You Wish", author: "Cary Elwes"))

      assert [best] = matches["work"]["candidates"]
      assert best["score"] > 0.9
    end

    # The other direction of the same rule: the tags carry the subtitle
    # ("House of Earth and Blood: The Crescent City, Book 1" is the dominant
    # real-world tag shape) and the catalogue is bare.
    test "a bare catalogue title scores exact against a subtitled tag" do
      patch_work_results([
        book("House of Earth and Blood", ["Sarah J. Maas"]),
        book("House of Earth and Blood, House of Sky and Breath", ["Sarah J. Maas"])
      ])

      %{matches: matches} =
        AutoMatch.match(
          item(
            title: "House of Earth and Blood: The Crescent City, Book 1",
            author: "Sarah J. Maas"
          )
        )

      assert [best | _rest] = matches["work"]["candidates"]
      assert best["title"] == "House of Earth and Blood"
      assert best["score"] > 0.95
      assert matches["work"]["confidence"] > 0.8
    end

    test "a summary with the right head is still not the book" do
      patch_work_results([book("As You Wish: Summary and Analysis", ["Somebody Else"])])

      %{matches: matches} = AutoMatch.match(item(title: "As You Wish", author: "Cary Elwes"))

      assert [companion] = matches["work"]["candidates"]
      assert companion["score"] < 0.4
    end

    # rreading-glasses says "Cast Under an Alien Sun" where Hardcover writes
    # the subtitle out; exact title equality read two records of one book as
    # near-tied rivals and the doubt penalty fired on a corroborated match.
    test "a subtitle variant of one book corroborates rather than rivals" do
      patch_work_results([
        book("Cast Under an Alien Sun", ["Olan Thorensen"]),
        book("Cast Under an Alien Sun: Destiny's Crucible, Book 1", ["Olan Thorensen"])
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "Cast Under an Alien Sun", author: "Olan Thorensen"))

      assert matches["work"]["confidence"] > 0.9
    end

    # "TJ Klune" and "T.J. Klune" are two providers' spellings of one human,
    # and treating them as different authors kept two records of one book
    # from corroborating each other.
    test "initials with and without dots are one person" do
      patch_work_results([
        book("The House in the Cerulean Sea", ["TJ Klune"]),
        book("The House in the Cerulean Sea", ["T.J. Klune"])
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "The House in the Cerulean Sea", author: "TJ Klune"))

      assert matches["work"]["confidence"] > 0.9
    end

    # rreading-glasses credits As You Wish to "Cary Elwes" and Hardcover to
    # "Cary Elwes, Joe Layden". Strict set equality read that as a rival and
    # doubted a match both databases had confirmed.
    test "a record naming fewer of the same authors corroborates" do
      patch_work_results([
        book("As You Wish", ["Cary Elwes"]),
        book("As You Wish", ["Cary Elwes", "Joe Layden"])
      ])

      %{matches: matches} = AutoMatch.match(item(title: "As You Wish", author: "Cary Elwes"))

      assert matches["work"]["confidence"] > 0.9
    end

    # The loop's proving case, measured live on the operator's Wayfarers
    # file: the tag says "Wayfarers, Book 1", round 1's "winner" is a
    # single-source series omnibus at 0.594, and Hardcover's work record and
    # Audible's recording record independently answer "The Long Way to a
    # Small, Angry Planet". Corroboration — not similarity — is what
    # qualifies a record to contribute the round-2 query (0.368 → 1.0 live).
    test "cross-level consensus refines the query and settles a shelf label" do
      omnibus = book("The Complete Wayfarers Series Collection", ["Becky Chambers"])
      long_way = book("The Long Way to a Small, Angry Planet", ["Becky Chambers"])

      long_way_rec =
        book("The Long Way to a Small, Angry Planet", ["Becky Chambers"],
          narrators: ["Rachel Dulude"]
        )

      patch(Providers, :search_books, fn id, query, _opts ->
        label? = String.contains?(to_string(query), "Wayfarers")

        cond do
          work_provider?(id) and label? -> {:ok, [omnibus, long_way]}
          work_provider?(id) -> {:ok, [long_way]}
          true -> {:ok, [long_way_rec]}
        end
      end)

      %{matches: matches} =
        AutoMatch.match(item(title: "Wayfarers, Book 1", author: "Becky Chambers"))

      work = matches["work"]
      assert [best | _rest] = work["candidates"]
      assert best["title"] == "The Long Way to a Small, Angry Planet"
      assert work["confidence"] > 0.8

      # the form reports the search that produced the winning evidence
      assert work["query"] =~ "The Long Way"

      # and round 1's evidence is still on the record — rounds add, never
      # remove, so nothing an operator might tick can vanish
      assert Enum.any?(
               work["candidates"],
               &(&1["title"] == "The Complete Wayfarers Series Collection")
             )
    end

    # The operator's fear, verified live before this existed: a series is
    # matched by its famous first book, so "Wayfarers, Book 4" offered and
    # scored book 1. A label naming a series and a number is an IDENTITY —
    # the candidate at that number wins, siblings at other numbers sink, and
    # box-set ranges ("1-4") stay neutral.
    test "a numbered series label matches its own volume, not the famous first book" do
      patch_work_results([
        book("The Long Way to a Small, Angry Planet", ["Becky Chambers"],
          series: [%Provider.Series{name: "Wayfarers", number: Decimal.new(1)}]
        ),
        book("The Galaxy, and the Ground Within", ["Becky Chambers"],
          series: [%Provider.Series{name: "Wayfarers", number: Decimal.new(4)}]
        ),
        book("The Wayfarers Series", ["Becky Chambers"],
          series: [%Provider.Series{name: "Wayfarers", number: "1-4"}]
        )
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "Wayfarers, Book 4", author: "Becky Chambers"))

      assert [best | rest] = matches["work"]["candidates"]
      assert best["title"] == "The Galaxy, and the Ground Within"
      assert best["score"] == 1.0
      assert matches["work"]["confidence"] > 0.65

      first_book = Enum.find(rest, &(&1["title"] == "The Long Way to a Small, Angry Planet"))
      assert first_book["score"] < 0.4
    end

    test "a label-tagged later volume never offers the first book from the shelf" do
      insert(:book,
        title: "The Long Way to a Small, Angry Planet",
        book_authors: [
          build(:book_author,
            author: build(:author, name: "Becky Chambers", person: build(:person))
          )
        ],
        series_books: [
          build(:series_book, book_number: 1, series: build(:series, name: "Wayfarers"))
        ]
      )

      %{matches: labeled} =
        AutoMatch.match(item(title: "Wayfarers, Book 4", author: "Becky Chambers"))

      %{matches: first} =
        AutoMatch.match(item(title: "Wayfarers, Book 1", author: "Becky Chambers"))

      # the wrong sibling is not offered; the right one still is
      assert labeled["work"]["local"] == []
      assert [%{"title" => "The Long Way to a Small, Angry Planet"}] = first["work"]["local"]
    end

    # The series is named after its first book, so the series TAG smuggled
    # book 1's whole title into the title-evidence word set: "Children of
    # Memory" (series-tagged "Children of Time") offered the shelved
    # Children of Time as "a book you already have". Title evidence must
    # come from what the file calls the BOOK; series words belong to the
    # series arm, which has its own label and volume guards.
    test "a series named after book one does not offer book one for its siblings" do
      insert(:book,
        title: "Children of Time",
        book_authors: [
          build(:book_author,
            author: build(:author, name: "Adrian Tchaikovsky", person: build(:person))
          )
        ],
        series_books: [
          build(:series_book, book_number: 1, series: build(:series, name: "Children of Time"))
        ]
      )

      item = %InboxItem{
        path: "/downloads/03 Children of Memory",
        tags: %{
          "book_title" => "Children of Memory",
          "authors" => ["Adrian Tchaikovsky"],
          "series" => "Children of Time",
          "asin" => nil
        }
      }

      %{matches: matches} = AutoMatch.match(item)

      assert matches["work"]["local"] == []
    end

    test "a numbered folder does not offer the wrong Kushiel volume" do
      insert(:book,
        title: "Kushiel's Dart",
        book_authors: [
          build(:book_author,
            author: build(:author, name: "Jacqueline Carey", person: build(:person))
          )
        ],
        series_books: [
          build(:series_book,
            book_number: 1,
            series: build(:series, name: "Kushiel's Legacy: Phedre Trilogy")
          ),
          build(:series_book, book_number: 1, series: build(:series, name: "Kushiel's Universe"))
        ]
      )

      item = %InboxItem{
        path: "/downloads/2 - Kushiel's Chosen",
        tags: %{
          "book_title" => "Kushiel's Chosen",
          "authors" => ["Jacqueline Carey"],
          "series" => "Kushiel's Legacy",
          "series_number" => "2",
          "asin" => nil
        }
      }

      %{matches: matches} = AutoMatch.match(item)

      assert matches["work"]["local"] == []
    end

    # A lone provider's hit is not consensus, however bad round 1 looks:
    # refining from an uncorroborated record is how a bad round-1 match
    # becomes a confidently wrong round-2 query.
    test "a lone unconfident hit refines nothing" do
      junk = book("01 Mistrunner", ["M.R. Ghanoonparvar"])

      patch(Providers, :search_books, fn id, _query, _opts ->
        if work_provider?(id), do: {:ok, [junk]}, else: {:ok, []}
      end)

      %{matches: matches} = AutoMatch.match(item(title: "Some Obscure Book", author: "Nobody"))

      assert matches["work"]["query_fields"]["title"] == "Some Obscure Book"
      assert [%{"title" => "01 Mistrunner"}] = matches["work"]["candidates"]
    end

    # Measured on the operator's Limitless: the right book at 0.938 sat
    # doubted at 0.583 under Jim Kwik's identically-titled self-help book.
    # The query's author adjudicates a same-title tie.
    test "a same-titled book by a plainly different author is not doubt" do
      patch_work_results([book("Limitless", ["Alan Glynn"]), book("Limitless", ["Jim Kwik"])])

      %{matches: matches} = AutoMatch.match(item(title: "Limitless", author: "Alan Glynn"))

      assert matches["work"]["confidence"] > 0.8
    end

    test "two same-titled books with no author in hand stay ambiguous" do
      patch_work_results([book("Origin", ["Dan Brown"]), book("Origin", ["Jessica Khoury"])])

      %{matches: matches} = AutoMatch.match(item(title: "Origin"))

      assert matches["work"]["confidence"] < 0.65
    end

    # "Spark Notes" spelled the marker as two words and evaded it — it sat
    # at 0.698 as the only thing keeping the right work under the bar.
    test "a companion marker split into words still subtracts" do
      patch_work_results([
        book("Harry Potter and the Sorcerer's Stone", ["J.K. Rowling"]),
        book("Spark Notes Harry Potter and the Sorcerer's Stone", ["J.K. Rowling"])
      ])

      %{matches: matches} =
        AutoMatch.match(
          item(title: "Harry Potter and the Sorcerer's Stone", author: "J.K. Rowling")
        )

      assert [_best, sparknotes] = matches["work"]["candidates"]
      assert sparknotes["score"] < 0.4
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

  # The third level. Everything the form does well it does by asking outcome,
  # evidence and preference; people used to get a name string and nothing
  # else, which is why proposed people arrived with no face and no biography
  # and every import ended with a trip to the person form.
  describe "match/1 people" do
    setup do
      patch(Providers, :search_books, fn _id, _query, _opts -> {:ok, []} end)
      patch(Providers, :editions, fn _id, _work_id, _opts -> {:ok, []} end)
      patch(Providers, :book_details, fn _id, _book_id, _opts -> {:error, :not_stubbed} end)
      patch(Providers, :search_authors, fn _id, _query, _opts -> {:ok, []} end)
      patch(Providers, :author_details, fn _id, _author_id, _opts -> {:error, :not_stubbed} end)
      :ok
    end

    test "asks about the authors the work names and the narrators the recording names" do
      patch_work_results([book("Neuromancer", ["William Gibson"])])
      patch_people(%{"William Gibson" => author("William Gibson", "Wrote it")})

      %{matches: matches} =
        AutoMatch.match(
          item(title: "Neuromancer", author: "William Gibson", narrator: "Robertson Dean")
        )

      assert %{"williamgibson" => gibson} = matches["people"]
      assert gibson["roles"] == ["author"]
      assert [candidate | _rest] = gibson["candidates"]
      assert candidate["name"] == "William Gibson"

      # the file named the reader, so the reader is a question too
      assert %{"robertsondean" => dean} = matches["people"]
      assert dean["roles"] == ["narrator"]
    end

    # One human, two credits — the self-narrated case. The draft stores them
    # as one `PersonDecision`; searching them twice would be the same bug on
    # the matching side.
    test "an author who reads their own book is one person with two roles" do
      # both levels at once: the work names the author, the recording names
      # the reader, and they are the same human
      patch_results(
        work: [book("Legends & Lattes", ["Travis Baldree"])],
        recording: [book("Legends & Lattes", ["Travis Baldree"], narrators: ["Travis Baldree"])]
      )

      patch_people(%{"Travis Baldree" => author("Travis Baldree", "Wrote and read it")})

      %{matches: matches} = AutoMatch.match(item(title: "Legends & Lattes"))

      assert map_size(matches["people"]) == 1
      assert %{"travisbaldree" => baldree} = matches["people"]
      assert baldree["roles"] == ["author", "narrator"]
    end

    # The rule that makes searching people during matching affordable at all:
    # the operator's full-cast Harry Potter credits fifteen actors who recur
    # across seven books, so without this every import re-asks every provider
    # about the same fifteen humans.
    test "somebody already in the library is never searched" do
      insert(:person, name: "William Gibson")
      patch_work_results([book("Neuromancer", ["William Gibson"])])
      patch_people(%{"William Gibson" => author("William Gibson", "Wrote it")})

      %{matches: matches} = AutoMatch.match(item(title: "Neuromancer", author: "William Gibson"))

      assert %{"williamgibson" => gibson} = matches["people"]
      assert [%{"source" => "local"}] = gibson["local"]
      assert gibson["candidates"] == []
      # not "found nothing" — never asked
      assert gibson["providers"] == []
      refute_called(Providers.search_authors(_id, "William Gibson", _opts))
    end

    # A doubted level ticks no record, so `Seed` credits the *tags'* narrator
    # — measured on the operator's Becky Chambers file, where the recording
    # match is 12% and the file says "Patricia Rodriguez" while the top record
    # says "Rachel Dulude". Deriving from records alone searched the wrong
    # human and left the one actually created with no photo at all.
    test "asks about the tags' narrator too, not only the record's" do
      patch_recording_results([
        book("The Long Way to a Small, Angry Planet", ["Becky Chambers"],
          narrators: ["Rachel Dulude"]
        )
      ])

      %{matches: matches} =
        AutoMatch.match(item(title: "Wayfarers, Book 1", narrator: "Patricia Rodriguez"))

      assert Map.has_key?(matches["people"], "patriciarodriguez")
      assert Map.has_key?(matches["people"], "racheldulude")
    end

    test "a cast label is never a person to go and find" do
      %{matches: matches} =
        AutoMatch.match(
          item(title: "Harry Potter and the Sorcerer's Stone", narrator: "Full Cast")
        )

      refute Map.has_key?(matches["people"], "full cast")
    end

    test "records what each provider was asked and what it said" do
      patch_work_results([book("Neuromancer", ["William Gibson"])])

      patch(Providers, :search_authors, fn _id, _query, _opts -> {:error, :rate_limited} end)

      %{matches: matches} = AutoMatch.match(item(title: "Neuromancer", author: "William Gibson"))

      assert %{"williamgibson" => gibson} = matches["people"]
      assert Enum.all?(gibson["providers"], &(&1["status"] == "failed"))
    end
  end

  describe "person_proposal/1" do
    # Person search is recall-first on purpose — anything sharing a name token
    # is offered, which is right for a grid a human reads and wrong for an
    # automatic choice. Measured on the operator's library: Audnexus answers
    # "Rachel Dulude" with Rachel Aukes first, and "Jefferson Mays" with
    # Jefferson Morley, Jefferson Bethke and Thomas Jefferson before Wikidata's
    # actual actor.
    test "only a candidate who is actually that person may be proposed" do
      person = %{
        "name" => "Rachel Dulude",
        "candidates" => [
          candidate("audnexus", "Rachel Aukes", ["aukes.jpg"], "Bestselling author"),
          candidate("audnexus", "Rachel Coles", ["coles.jpg"], "Lives in Denver")
        ]
      }

      assert AutoMatch.person_proposal(person) == %{}
    end

    test "takes the first provider that has one, in the operator's priority order" do
      person = %{
        "name" => "Jefferson Mays",
        "candidates" => [
          candidate("audnexus", "Jefferson Morley", ["morley.jpg"], "Wrote Scorpions' Dance"),
          candidate("wikidata", "Jefferson Mays", ["mays.jpg"], "An American actor")
        ]
      }

      assert %{
               image_url: "mays.jpg",
               image_source: "provider:wikidata",
               description: "An American actor",
               description_source: "provider:wikidata"
             } = AutoMatch.person_proposal(person)
    end

    # The database with the best portrait is routinely not the one with the
    # best prose — measured on James S.A. Corey, whose photo comes from
    # rreading-glasses and whose biography has to come from Hardcover.
    test "the photo and the biography are chosen independently" do
      person = %{
        "name" => "James S. A. Corey",
        "candidates" => [
          # rreading-glasses returns the literal string "N/A" where it has no
          # biography; storing that as somebody's life story is worse than
          # leaving it blank, because blank is visibly unfinished
          candidate("rreading_glasses", "James S.A. Corey", ["goodreads.jpg"], "N/A"),
          candidate("hardcover", "James S. A. Corey", [], "The pen name of two authors")
        ]
      }

      assert %{
               image_url: "goodreads.jpg",
               image_source: "provider:rreading_glasses",
               description: "The pen name of two authors",
               description_source: "provider:hardcover"
             } = AutoMatch.person_proposal(person)
    end

    test "nothing found is nothing proposed" do
      assert AutoMatch.person_proposal(nil) == %{}
      assert AutoMatch.person_proposal(%{"name" => "Nobody", "candidates" => []}) == %{}
    end
  end

  defp item(opts) do
    %InboxItem{
      path: "/downloads/#{Keyword.get(opts, :title, "Unknown")}",
      tags:
        %{
          "book_title" => opts[:title],
          "authors" => (opts[:author] && [opts[:author]]) || [],
          "narrators" => (opts[:narrator] && [opts[:narrator]]) || [],
          "asin" => opts[:asin]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

  defp author(name, description, images \\ ["photo.jpg"]) do
    %Provider.Author{
      provider: "test",
      id: "a-#{:erlang.phash2(name)}",
      name: name,
      description: description,
      image_urls: images
    }
  end

  # Person search hydrates every plausible hit, so both calls need answering.
  defp patch_people(by_name) do
    patch(Providers, :search_authors, fn _id, query, _opts ->
      {:ok, by_name |> Map.get(query, []) |> List.wrap()}
    end)

    patch(Providers, :author_details, fn _id, id, _opts ->
      case Enum.find(Map.values(by_name), &(&1.id == id)) do
        nil -> {:error, :not_found}
        found -> {:ok, found}
      end
    end)
  end

  defp candidate(provider_id, name, images, description) do
    %{
      "source" => "provider:#{provider_id}",
      "provider_name" => provider_id,
      "name" => name,
      "images" => images,
      "description" => description
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

  # Both levels in one call. The two helpers above each patch `search_books`
  # outright, so calling them in turn silently keeps only the second — which
  # is never what a test wanting results at both levels meant.
  defp patch_results(opts) do
    patch(Providers, :search_books, fn id, _query, _opts ->
      if work_provider?(id),
        do: {:ok, Keyword.get(opts, :work, [])},
        else: {:ok, Keyword.get(opts, :recording, [])}
    end)
  end

  defp work_provider?(id), do: id in ["rreading_glasses", "hardcover"]
end
