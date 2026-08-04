defmodule Ambry.Inbox.DraftTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  defp item(attrs) do
    %InboxItem{path: "/downloads/Some Release", files: ["/downloads/Some Release/book.m4b"]}
    |> Map.merge(attrs)
    |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))
  end

  defp provider_candidate(attrs) do
    Map.merge(
      %{
        "source" => "provider:hardcover",
        "provider_name" => "Hardcover",
        "id" => "hc-1",
        "title" => "Leviathan Wakes",
        "authors" => ["James S.A. Corey"],
        "published" => "2011-06-15",
        "published_format" => "full",
        "score" => 0.95
      },
      attrs
    )
  end

  defp matches(work_candidates, opts \\ []) do
    %{
      "work" => %{
        "candidates" => work_candidates,
        "confidence" => Keyword.get(opts, :confidence, 0.95),
        "query" => "q"
      },
      "recording" => %{
        "candidates" => Keyword.get(opts, :recording, []),
        # A recording match only gets to fill fields in when it's believed;
        # tests that want its metadata used have to say so.
        "confidence" => Keyword.get(opts, :recording_confidence, 0.0)
      }
    }
  end

  describe "the invariant" do
    test "a draft with an unresolved decision is not importable" do
      item = item(%{matches: matches([]), tags: %{}})
      draft = Seed.build(item)

      refute Draft.resolved?(draft)
      assert Enum.any?(Draft.unresolved(draft), &(&1.label == "Which book"))
    end

    test "unresolved names the missing decision rather than just failing" do
      # a title but no date anywhere: the refusal approval used to throw at
      # the last moment is a visible decision instead
      item = item(%{matches: matches([]), tags: %{"book_title" => "Wool"}})
      draft = Seed.build(item)

      assert %{label: "First published", state: :missing} =
               Enum.find(Draft.unresolved(draft), &(&1.label == "First published"))
    end

    test "a fully-seeded draft off a strong provider match is importable" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      draft = Seed.build(item)

      assert Draft.unresolved(draft) == []
      assert Draft.resolved?(draft)
    end

    test "progress counts resolved against total" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      %{resolved: resolved, total: total} = Draft.progress(Seed.build(item))

      assert total > 0
      assert resolved == total
    end
  end

  describe "work identity" do
    test "a strong local hit links the existing book rather than creating one" do
      book = insert(:book, title: "Leviathan Wakes")

      candidates = [
        %{"source" => "local", "id" => book.id, "title" => "Leviathan Wakes", "score" => 1.0}
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert draft.work.mode == :link
      assert draft.work.book_id == book.id
      assert draft.work.approved
    end

    test "a close runner-up leaves the identity for the operator" do
      candidates = [
        provider_candidate(%{"id" => "a", "score" => 0.92}),
        provider_candidate(%{"id" => "b", "score" => 0.91})
      ]

      draft = Seed.build(item(%{matches: matches(candidates, confidence: 0.5), tags: %{}}))

      refute draft.work.approved
      assert Enum.any?(Draft.unresolved(draft), &(&1.label == "Which book"))
    end

    test "linking a book does not re-decide the book's own fields" do
      book = insert(:book, title: "Leviathan Wakes")

      candidates = [
        %{"source" => "local", "id" => book.id, "title" => "Leviathan Wakes", "score" => 1.0}
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      refute Enum.any?(Draft.unresolved(draft), &(&1.label == "Title"))
      refute Enum.any?(Draft.unresolved(draft), &(&1.section == :work and &1.label == "Author"))
    end
  end

  describe "credits — the import resolves credits, not personhood" do
    test "an exact identity match links it and settles" do
      author = insert(:author, name: "Brandon Sanderson")

      candidates = [provider_candidate(%{"authors" => [author.name]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [credit] = draft.work.authors
      assert credit.mode == :link
      assert credit.identity_id == author.id
      assert Credit.resolved?(credit)
    end

    test "a brand-new provider name creates one identity backed by one new person" do
      candidates = [provider_candidate(%{"authors" => ["Nobody In This Library"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [credit] = draft.work.authors
      assert credit.mode == :create
      assert [person_ref] = credit.people
      assert person_ref.person_id == nil
      assert person_ref.name == "Nobody In This Library"
      assert credit.approved
    end

    test "a name from tags alone never auto-creates a person" do
      # tag splitting is knowingly imperfect ("Sanderson, Brandon"), so a
      # tag-derived name is a proposal, never a settled decision
      item = item(%{matches: matches([]), tags: %{"authors" => ["Sanderson, Brandon"]}})
      draft = Seed.build(item)

      assert [credit] = draft.work.authors
      refute credit.approved
      assert Enum.any?(Draft.unresolved(draft), &(&1.label =~ "Sanderson, Brandon"))
    end

    test "a Person exists but the identity does not — always the operator's call" do
      # the person is a narrator; this book credits them as an author
      person = insert(:person, name: "Neil Gaiman", authors: [], narrators: [])

      candidates = [provider_candidate(%{"authors" => [person.name]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [credit] = draft.work.authors
      refute credit.approved
      assert credit.mode == :create
    end

    test "two or more people behind one credit is just a longer list" do
      # the composite case, which needs no special pathway: one Author, two
      # People, expressed as two entries in the same control
      credit = %Credit{
        name: "James S.A. Corey",
        kind: :author,
        mode: :create,
        approved: true,
        people: [
          %Draft.PersonRef{name: "Daniel Abraham"},
          %Draft.PersonRef{name: "Ty Franck"}
        ]
      }

      assert Credit.resolved?(credit)
      assert length(credit.people) == 2
    end

    # Validation gates *saving*, the invariant gates *importing*. A half-made
    # credit has to be storable — otherwise the operator couldn't add a second
    # person and then name them — so only an approved one is rejected.
    test "a half-made credit saves; an approved one with nobody behind it does not" do
      in_progress =
        Credit.changeset(%Credit{}, %{name: "Somebody", kind: :author, mode: :create, people: []})

      assert in_progress.valid?
      refute Credit.resolved?(Ecto.Changeset.apply_changes(in_progress))

      approved =
        Credit.changeset(%Credit{}, %{
          name: "Somebody",
          kind: :author,
          mode: :create,
          people: [],
          approved: true
        })

      refute approved.valid?
      assert %{people: ["needs at least one person behind it"]} = errors_on(approved)
    end

    test "a person row nobody has named yet keeps the credit unresolved" do
      credit = %Credit{
        name: "James S.A. Corey",
        kind: :author,
        mode: :create,
        approved: true,
        people: [%Draft.PersonRef{name: "Daniel Abraham"}, %Draft.PersonRef{name: ""}]
      }

      refute Credit.resolved?(credit)
    end
  end

  describe "series numbers are never invented" do
    test "a series with no number anywhere stays unresolved" do
      candidates = [provider_candidate(%{"series" => ["The Expanse"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [link] = draft.work.series
      refute SeriesLink.resolved?(link)
      assert link.number == nil
      assert SeriesLink.state(link) == :missing
    end

    test "a number from the tags settles it" do
      candidates = [provider_candidate(%{"series" => ["The Expanse"]})]

      draft =
        Seed.build(item(%{matches: matches(candidates), tags: %{"series_number" => "1"}}))

      assert [link] = draft.work.series
      assert link.number == "1"
      assert SeriesLink.resolved?(link)
      assert Decimal.equal?(SeriesLink.decimal(link), Decimal.new(1))
    end

    test "each series is its own decision" do
      candidates = [
        provider_candidate(%{"series" => ["The Expanse", "The Expanse (Chronological)"]})
      ]

      draft =
        Seed.build(item(%{matches: matches(candidates), tags: %{"series_number" => "1"}}))

      assert length(draft.work.series) == 2
    end

    test "a series the linked book already has is not offered again" do
      series = insert(:series)
      book = insert(:book, series_books: [build(:series_book, series: series, book_number: 1)])

      candidates = [
        %{"source" => "local", "id" => book.id, "title" => book.title, "score" => 1.0}
      ]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"series" => series.name, "series_number" => "1"}
          })
        )

      assert draft.work.series == []
    end
  end

  describe "scalars" do
    test "sources that agree settle the field" do
      candidates = [provider_candidate(%{"title" => "Leviathan Wakes"})]

      draft =
        Seed.build(
          item(%{matches: matches(candidates), tags: %{"book_title" => "leviathan wakes"}})
        )

      assert draft.work.title.approved
      assert draft.work.title.value == "Leviathan Wakes"
    end

    test "sources that disagree do not" do
      candidates = [provider_candidate(%{"title" => "Leviathan Wakes"})]

      draft =
        Seed.build(
          item(%{matches: matches(candidates), tags: %{"book_title" => "Caliban's War"}})
        )

      refute draft.work.title.approved
      assert length(draft.work.title.candidates) >= 2
    end

    test "an optional field nobody proposed is waived, not outstanding" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      assert draft.recording.publisher.approved
      assert draft.recording.publisher.value == nil
      refute Enum.any?(Draft.unresolved(draft), &(&1.label == "Publisher"))
    end

    test "embedded art and a provider cover is a choice, not a winner" do
      candidates = [provider_candidate(%{})]

      recording = [
        %{
          "source" => "provider:audible",
          "provider_name" => "Audible",
          "id" => "B01",
          "cover_url" => "https://example.test/cover.jpg",
          "score" => 0.9
        }
      ]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates, recording: recording, recording_confidence: 0.95),
            tags: %{"has_cover_art" => true}
          })
        )

      refute draft.recording.cover.approved
      assert length(draft.recording.cover.candidates) == 2
    end

    # The wrong recording of the right book is the most common recording-level
    # failure and the hardest to notice afterwards, so a candidate whose
    # narrator disagrees with the file's is shown but never allowed to
    # describe it.
    test "a recording with the wrong narrator fills nothing in" do
      recording = [
        %{
          "source" => "provider:audible",
          "provider_name" => "Audible",
          "id" => "B01",
          "title" => "Neuromancer",
          "narrators" => ["Robertson Dean"],
          "publisher" => "Penguin Audio",
          "published" => "2011-06-30",
          "cover_url" => "https://example.test/cover.jpg",
          "score" => 0.5
        }
      ]

      draft =
        Seed.build(
          item(%{
            matches:
              matches([provider_candidate(%{})],
                recording: recording,
                recording_confidence: 0.5
              ),
            tags: %{"narrators" => ["Jeff Harding"]}
          })
        )

      # offered, so the operator can still choose it
      assert length(draft.recording.candidates) == 1
      # but nothing of its metadata was adopted
      assert draft.recording.publisher.value == nil
      assert draft.recording.published.value == nil
      assert draft.recording.cover.value == nil

      # and the reason is recorded rather than left as an unexplained set of
      # empty fields, which is indistinguishable from having found nothing
      assert draft.recording.doubt == :narrator_conflict
      assert draft.recording.doubt_detail =~ "Jeff Harding"
      assert draft.recording.doubt_detail =~ "Robertson Dean"

      # a doubted identity is a real question, so it stays open
      refute draft.recording.approved

      assert Enum.any?(
               Draft.unresolved(draft),
               &(&1.label == "Which recording this is" and &1.state == :unconfirmed)
             )
    end

    test "finding nothing at all is settled, and says so" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      # plenty of perfectly good rips are in no catalogue — that's an answer,
      # not an outstanding question
      assert draft.recording.doubt == :nothing_found
      assert draft.recording.approved
    end
  end

  describe "choosing a candidate" do
    test "picking a different book refills the work's fields from it" do
      candidates = [
        provider_candidate(%{"id" => "hc-1", "title" => "Leviathan Wakes"}),
        provider_candidate(%{
          "id" => "hc-2",
          "title" => "Caliban's War",
          "published" => "2012-06-26",
          "score" => 0.6
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert item.draft.work.title.value == "Leviathan Wakes"
      assert item.draft.work.selected_id == "hc-1"

      draft = Draft.Edit.choose_work(item.draft, item, "provider:hardcover", "hc-2")

      # the list is a question with one right answer, so choosing has to move
      # the fields — it used to only flip `mode`, which is why every row
      # rendered as chosen and clicking one did nothing visible
      assert draft.work.title.value == "Caliban's War"
      assert draft.work.published.value == "2012-06-26"
      assert draft.work.selected_id == "hc-2"
      assert draft.work.approved
    end

    test "a typed value survives choosing a different book" do
      candidates = [
        provider_candidate(%{"id" => "hc-1"}),
        provider_candidate(%{"id" => "hc-2", "title" => "Caliban's War", "score" => 0.6})
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      {:ok, item} =
        Inbox.update_draft(item, %{
          "work" => %{"title" => %{"value" => "What I Actually Want"}}
        })

      draft = Draft.Edit.choose_work(item.draft, item, "provider:hardcover", "hc-2")

      # 1d again: curation outranks any source, including a source the
      # operator just picked
      assert draft.work.title.value == "What I Actually Want"
      assert draft.work.title.source == "manual"
    end

    test "clicking the already-chosen book confirms rather than resetting" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      touched = Draft.Edit.approve_credit(item.draft, :work, 0, true)
      assert Enum.at(touched.work.authors, 0).approved

      draft = Draft.Edit.choose_work(touched, item, "provider:hardcover", "hc-1")

      assert Enum.at(draft.work.authors, 0).approved
    end

    test "choosing a recording settles the book it is known to be of" do
      work = [
        provider_candidate(%{"id" => "hc-1"}),
        provider_candidate(%{"id" => "hc-2", "title" => "Caliban's War", "score" => 0.6})
      ]

      recording = [
        %{
          "source" => "provider:hardcover",
          "provider_name" => "Hardcover editions",
          "id" => "ed-9",
          "title" => "Caliban's War",
          "narrators" => ["Jefferson Mays"],
          "publisher" => "Orbit",
          "published" => "2012-06-26",
          "score" => 0.4,
          # editions come out of a work's own list, so which work is not a
          # second question
          "of_work" => %{"source" => "provider:hardcover", "id" => "hc-2"}
        }
      ]

      item =
        item(%{
          matches: matches(work, recording: recording, recording_confidence: 0.4),
          tags: %{}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.work.selected_id == "hc-1"

      draft = Draft.Edit.choose_recording(item.draft, item, "provider:hardcover", "ed-9")

      assert draft.recording.selected_id == "ed-9"
      assert draft.recording.publisher.value == "Orbit"
      # a file is a recording of exactly one work, so identifying the
      # recording answers the book question too
      assert draft.work.selected_id == "hc-2"
      assert draft.work.title.value == "Caliban's War"
    end

    test "a recording in no catalogue is a real answer" do
      recording = [
        %{
          "source" => "provider:audible",
          "id" => "B01",
          "title" => "Neuromancer",
          "narrators" => ["Robertson Dean"],
          "score" => 0.5
        }
      ]

      item =
        item(%{
          matches:
            matches([provider_candidate(%{})], recording: recording, recording_confidence: 0.5),
          tags: %{"narrators" => ["Jeff Harding"]}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      refute item.draft.recording.approved

      draft = Draft.Edit.choose_uncatalogued(item.draft, item)

      assert draft.recording.approved
      assert draft.recording.selected_source == nil
      assert Draft.Recording.uncatalogued?(draft.recording)
    end

    test "taking the top suggestion never adopts a doubted recording" do
      recording = [
        %{
          "source" => "provider:audible",
          "id" => "B01",
          "title" => "Neuromancer",
          "narrators" => ["Robertson Dean"],
          "publisher" => "Penguin Audio",
          "score" => 0.5
        }
      ]

      item =
        item(%{
          matches:
            matches([provider_candidate(%{})], recording: recording, recording_confidence: 0.5),
          tags: %{"narrators" => ["Jeff Harding"]}
        })

      draft = item |> Seed.build() |> Draft.Edit.approve_all()

      # the leading candidate here is, by construction, the wrong recording of
      # the right book — the one thing this button must not paper over
      refute draft.recording.approved
      assert draft.recording.publisher.value == nil
    end
  end

  describe "sources that agree" do
    test "a format label is not a disagreement" do
      # Audible titles carry "(Unabridged)" and work-level providers don't, so
      # treating the two as rival answers made the operator arbitrate a
      # non-question on a large share of imports
      draft =
        Seed.build(
          item(%{
            matches: matches([provider_candidate(%{"title" => "Neuromancer (Unabridged)"})]),
            tags: %{"book_title" => "Neuromancer"}
          })
        )

      assert draft.work.title.approved
      # and the clean spelling wins the field
      assert draft.work.title.value == "Neuromancer"
      # both are still offered, because the operator may want the other
      assert length(draft.work.title.candidates) == 2
    end

    test "genuinely different titles still disagree" do
      draft =
        Seed.build(
          item(%{
            matches: matches([provider_candidate(%{"title" => "Neuromancer"})]),
            tags: %{"book_title" => "Count Zero"}
          })
        )

      refute draft.work.title.approved
      assert Draft.Field.state(draft.work.title) == :ambiguous
    end
  end

  describe "series numbers" do
    test "a number the provider supplied settles the membership" do
      candidates = [
        provider_candidate(%{
          "series" => [%{"name" => "The Expanse", "number" => "1"}]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      # every provider we use reports the position; it was being thrown away
      # between the search result and the draft, so the inbox asked the
      # operator for a number nobody had to look up
      assert [link] = draft.work.series
      assert link.number == "1"
      assert SeriesLink.resolved?(link)
    end

    test "each series keeps its own number" do
      candidates = [
        provider_candidate(%{
          "series" => [
            %{"name" => "The Expanse", "number" => "1"},
            %{"name" => "The Expanse (Chronological)", "number" => "2"}
          ]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [first, second] = draft.work.series
      assert first.number == "1"
      assert second.number == "2"
    end

    test "a tag's number is not applied to a series the tag didn't name" do
      candidates = [
        provider_candidate(%{
          "series" => [%{"name" => "The Expanse"}, %{"name" => "Some Other Series"}]
        })
      ]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"series" => "The Expanse", "series_number" => "1"}
          })
        )

      assert [expanse, other] = draft.work.series
      assert expanse.number == "1"
      # the file said where this book sits in The Expanse and nothing at all
      # about the other one; borrowing the number would be inventing a fact
      assert other.number == nil
    end
  end

  describe "persistence" do
    test "a draft survives a round trip through the database" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      reloaded = Repo.get!(InboxItem, item.id)

      assert reloaded.draft.work.title.value == "Leviathan Wakes"
      assert [credit] = reloaded.draft.work.authors
      assert credit.name == "James S.A. Corey"
      assert Draft.resolved?(reloaded.draft)
    end

    test "ready is stored to match what the draft says" do
      resolved = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, resolved} = Inbox.prepare_draft(resolved)
      assert resolved.ready

      unresolved =
        item(%{path: "/downloads/Another", matches: matches([]), tags: %{}})

      {:ok, unresolved} = Inbox.prepare_draft(unresolved)
      refute unresolved.ready
    end

    test "preparing never overwrites a draft the operator has touched" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      {:ok, edited} =
        Inbox.update_draft(item, %{
          "work" => %{
            "title" => %{"value" => "Hand Typed", "source" => "manual", "approved" => true}
          }
        })

      assert edited.draft.work.title.value == "Hand Typed"

      {:ok, again} = Inbox.prepare_draft(edited)
      assert again.draft.work.title.value == "Hand Typed"
    end

    test "files changing under a draft marks it stale rather than re-seeding" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      moved = %{item | files: ["/downloads/Some Release/moved.m4b"]}
      stale = Seed.restale(item.draft, moved)

      assert stale.stale
      refute Draft.resolved?(stale)
      assert Enum.any?(Draft.unresolved(stale), &(&1.state == :stale))
    end
  end
end
