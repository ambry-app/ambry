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
        "local" => Keyword.get(opts, :local, []),
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
      assert Enum.any?(Draft.unresolved(draft), &(&1.label == "First published"))
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
      local = [%{"id" => book.id, "title" => "Leviathan Wakes", "score" => 1.0}]

      draft = Seed.build(item(%{matches: matches([], local: local), tags: %{}}))

      assert draft.work.mode == :link
      assert draft.work.book_id == book.id
      assert draft.work.approved
    end

    # Attaching a recording to the wrong existing book is worse than one
    # duplicate Book, and much harder to notice afterwards.
    test "a local book that only nearly matches is offered, never assumed" do
      book = insert(:book, title: "Leviathan Wakes")
      local = [%{"id" => book.id, "title" => "Leviathan Wakes", "score" => 0.8}]

      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})], local: local)}))

      assert draft.work.mode == :create
      refute draft.work.approved
    end

    test "weak records leave the new-book answer for the operator" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5})
      ]

      draft = Seed.build(item(%{matches: matches(candidates, confidence: 0.5), tags: %{}}))

      refute draft.work.approved
      assert Enum.any?(Draft.unresolved(draft), &(&1.label =~ "already have"))
    end

    test "linking a book does not re-decide the book's own fields" do
      book = insert(:book, title: "Leviathan Wakes")
      local = [%{"id" => book.id, "title" => "Leviathan Wakes", "score" => 1.0}]

      draft = Seed.build(item(%{matches: matches([], local: local), tags: %{}}))

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

      local = [%{"id" => book.id, "title" => book.title, "score" => 1.0}]

      draft =
        Seed.build(
          item(%{
            matches: matches([], local: local),
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

      # offered, so the operator can still tick it
      assert draft.recording.sources == []
      # and nothing of its metadata was adopted
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
               &(&1.label =~ "describe this recording" and &1.state == :unconfirmed)
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

  describe "ticking records" do
    test "ticking a second record adds its values without replacing the first" do
      candidates = [
        provider_candidate(%{"id" => "hc-1", "description" => "Hardcover's"}),
        provider_candidate(%{
          "source" => "provider:rreading_glasses",
          "provider_name" => "rreading-glasses",
          "id" => "rg-1",
          "title" => "Something Else Entirely",
          "description" => "rreading-glasses'",
          "score" => 0.4
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      # only the top record is ticked to begin with
      assert length(item.draft.work.sources) == 1

      draft = Draft.Edit.toggle_source(item.draft, item, :work, Enum.at(candidates, 1))

      assert length(draft.work.sources) == 2
      values = Enum.map(draft.recording.description.candidates, & &1.value)
      assert "Hardcover's" in values
      assert "rreading-glasses'" in values
    end

    test "un-ticking a record takes its values back out" do
      candidates = [provider_candidate(%{"description" => "Hardcover's"})]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert item.draft.recording.description.value == "Hardcover's"

      draft = Draft.Edit.toggle_source(item.draft, item, :work, hd(candidates))

      assert draft.work.sources == []
      assert draft.recording.description.candidates == []
    end

    test "a typed value survives the ticked set changing" do
      candidates = [provider_candidate(%{"id" => "hc-1"})]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      {:ok, item} =
        Inbox.update_draft(item, %{
          "work" => %{"title" => %{"value" => "What I Actually Want"}}
        })

      draft = Draft.Edit.toggle_source(item.draft, item, :work, hd(candidates))

      # 1d again: curation outranks any source, including the absence of one
      assert draft.work.title.value == "What I Actually Want"
      assert draft.work.title.source == "manual"
    end

    test "linking an existing book settles the first decision" do
      book = insert(:book, title: "Leviathan Wakes")
      local = [%{"id" => book.id, "title" => "Leviathan Wakes", "score" => 0.8}]

      item = item(%{matches: matches([provider_candidate(%{})], local: local)})
      {:ok, item} = Inbox.prepare_draft(item)
      refute item.draft.work.approved

      draft = Draft.Edit.link_book(item.draft, item, book.id)

      assert draft.work.mode == :link
      assert draft.work.book_id == book.id
      assert draft.work.approved
    end

    test "saying it is a different book settles it as new" do
      book = insert(:book, title: "Leviathan Wakes")
      local = [%{"id" => book.id, "title" => "Leviathan Wakes", "score" => 0.8}]

      item = item(%{matches: matches([provider_candidate(%{})], local: local)})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.new_book(item.draft, item)

      assert draft.work.mode == :create
      assert draft.work.book_id == nil
      assert draft.work.approved
    end

    test "ticking an edition ticks the work it came from" do
      work = [
        provider_candidate(%{"id" => "hc-1"}),
        provider_candidate(%{"id" => "hc-2", "title" => "Caliban's War", "score" => 0.4})
      ]

      recording = [
        %{
          "source" => "provider:hardcover",
          "provider_name" => "Hardcover editions",
          "id" => "ed-9",
          "title" => "Caliban's War",
          "narrators" => ["Jefferson Mays"],
          "publisher" => "Orbit",
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

      draft = Draft.Edit.toggle_source(item.draft, item, :recording, hd(recording))

      assert draft.recording.publisher.value == "Orbit"
      # a file is a recording of exactly one work, so identifying the
      # recording answers the book question too
      assert Enum.any?(draft.work.sources, &(&1.id == "hc-2"))
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

      draft = Draft.Edit.uncatalogued(item.draft, item)

      assert draft.recording.approved
      assert draft.recording.sources == []
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

      # the leading record here is, by construction, the wrong recording of
      # the right book — the one thing this button must not paper over
      refute draft.recording.approved
      assert draft.recording.publisher.value == nil
    end
  end

  describe "curation survives re-derivation" do
    # Field values are cheap to recompute; a credit is not. It may carry a
    # linked identity, a renamed pen name, or two people behind it — and
    # ticking any other record was rebuilding it from proposals and throwing
    # all of that away.
    test "ticking a recording record leaves curated authors alone" do
      work = [provider_candidate(%{"authors" => ["David Wong"]})]

      recording = [
        %{
          "source" => "provider:audible",
          "provider_name" => "Audible",
          "id" => "B01",
          "title" => "What the Hell Did I Just Read",
          "narrators" => ["Kirby Heyborne"],
          "score" => 0.9
        }
      ]

      item = item(%{matches: matches(work, recording: recording), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      # the operator sets up the pen name: one author, a differently-named
      # person behind it
      draft =
        item.draft
        |> Draft.Edit.set_person(:work, 0, 0, %{name: "Jason Pargin", person_id: nil})
        |> Draft.Edit.approve_credit(:work, 0, true)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      after_tick = Draft.Edit.toggle_source(item.draft, item, :recording, hd(recording))

      assert [credit] = after_tick.work.authors
      assert credit.name == "David Wong"
      assert [%{name: "Jason Pargin"}] = credit.people
      assert credit.approved
    end

    test "un-ticking a work record leaves a curated credit behind" do
      work = [provider_candidate(%{"authors" => ["David Wong"]})]

      item = item(%{matches: matches(work), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_credit(item.draft, :work, 0, "Jason Pargin")
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      after_untick = Draft.Edit.toggle_source(item.draft, item, :work, hd(work))

      assert [%{name: "Jason Pargin"}] = after_untick.work.authors
    end

    test "an untouched credit still follows the records" do
      work = [provider_candidate(%{"authors" => ["David Wong"]})]

      item = item(%{matches: matches(work), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      assert [_credit] = item.draft.work.authors

      after_untick = Draft.Edit.toggle_source(item.draft, item, :work, hd(work))

      # nobody curated it, so it goes when its source does
      assert after_untick.work.authors == []
    end
  end

  describe "choosing between chips" do
    # Two records from ONE provider both propose a release date. Keying the
    # choice on the provider selected both chips and could only ever apply
    # the first — the other value was unreachable.
    test "two proposals from one provider are separately choosable" do
      candidates = [
        provider_candidate(%{"id" => "a", "published" => "2017-10-03"}),
        provider_candidate(%{"id" => "b", "published" => "2018-05-01", "score" => 0.94})
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [first, second] = draft.work.published.candidates
      assert first.key != second.key

      chosen = Draft.Field.choose(draft.work.published, second.key)

      assert chosen.value == second.value
      assert Draft.Field.chose?(chosen, second)
      refute Draft.Field.chose?(chosen, first)
    end

    test "a chosen chip stays chosen when the ticked set changes" do
      candidates = [
        provider_candidate(%{"id" => "a", "published" => "2017-10-03"}),
        provider_candidate(%{"id" => "b", "published" => "2018-05-01", "score" => 0.94})
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      [_first, second] = item.draft.work.published.candidates
      draft = Draft.Edit.choose_field(item.draft, :work, :published, second.key)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      assert item.draft.work.published.value == "2018-05-01"

      # re-deriving because something else was ticked must not move a value
      # the operator picked
      after_reseed = Draft.Edit.resettle(item.draft, item)
      assert after_reseed.work.published.value == "2018-05-01"
    end
  end

  describe "mixing sources" do
    # Two providers agreeing on WHICH work this is do not agree on everything
    # about it. Collapsing them to a winner left the operator choosing between
    # one provider and the file's tags.
    test "a corroborating provider still gets to propose its own values" do
      candidates = [
        provider_candidate(%{
          "description" => "Hardcover's description",
          "cover_url" => "https://example.test/hardcover.jpg"
        }),
        provider_candidate(%{
          "source" => "provider:rreading_glasses",
          "provider_name" => "rreading-glasses",
          "id" => "rg-1",
          "description" => "rreading-glasses' description",
          "cover_url" => "https://example.test/rg.jpg"
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      values = Enum.map(draft.recording.description.candidates, & &1.value)
      assert "Hardcover's description" in values
      assert "rreading-glasses' description" in values

      covers = Enum.map(draft.recording.cover.candidates, & &1.value)
      assert "https://example.test/hardcover.jpg" in covers
      assert "https://example.test/rg.jpg" in covers
    end

    # The operator's example: description from a work-level provider, cover
    # from the recording-level one.
    test "the work's sources describe the recording too" do
      recording = [
        %{
          "source" => "provider:audible",
          "provider_name" => "Audible",
          "id" => "B01",
          "title" => "Leviathan Wakes",
          "narrators" => ["Jefferson Mays"],
          "cover_url" => "https://example.test/audible.jpg",
          "score" => 1.0
        }
      ]

      draft =
        Seed.build(
          item(%{
            matches:
              matches([provider_candidate(%{"description" => "The work-level description"})],
                recording: recording,
                recording_confidence: 1.0
              ),
            tags: %{}
          })
        )

      assert "The work-level description" in Enum.map(
               draft.recording.description.candidates,
               & &1.value
             )

      assert "https://example.test/audible.jpg" in Enum.map(
               draft.recording.cover.candidates,
               & &1.value
             )
    end

    # A work-level provider's date is the work's ORIGINAL publication date,
    # which is a different fact wearing the same name.
    test "the work's date is never offered as the recording's release date" do
      recording = [
        %{
          "source" => "provider:audible",
          "id" => "B01",
          "title" => "Leviathan Wakes",
          "narrators" => ["Jefferson Mays"],
          "published" => "2011-06-15",
          "score" => 1.0
        }
      ]

      draft =
        Seed.build(
          item(%{
            matches:
              matches([provider_candidate(%{"published" => "1999-01-02"})],
                recording: recording,
                recording_confidence: 1.0
              ),
            tags: %{}
          })
        )

      refute "1999-01-02" in Enum.map(draft.recording.published.candidates, & &1.value)
    end
  end

  describe "date precision" do
    # Year-only knowledge arrives as a literal January 1st from every source
    # that has it, so the tag date and the provider date were being reported
    # as rival opinions on a large share of imports.
    test "a January 1st date defers to a precise one in the same year" do
      draft =
        Seed.build(
          item(%{
            matches: matches([provider_candidate(%{"published" => "2017-10-03"})]),
            tags: %{"published" => "2017-01-01"}
          })
        )

      assert draft.work.published.approved
      assert draft.work.published.value == "2017-10-03"
    end

    test "the display format follows whichever source won the date" do
      draft =
        Seed.build(
          item(%{
            matches:
              matches([
                provider_candidate(%{
                  "published" => "2017-10-03",
                  "published_format" => "full"
                })
              ]),
            tags: %{"published" => "2017-01-01", "published_format" => "year"}
          })
        )

      # otherwise the two columns describing one fact disagree with each other
      assert draft.work.published_format.approved
      assert draft.work.published_format.value == "full"
    end

    test "two precise dates in one year genuinely disagree" do
      draft =
        Seed.build(
          item(%{
            matches: matches([provider_candidate(%{"published" => "2017-10-03"})]),
            tags: %{"published" => "2017-03-08"}
          })
        )

      refute draft.work.published.approved
    end

    test "different years disagree" do
      draft =
        Seed.build(
          item(%{
            matches: matches([provider_candidate(%{"published" => "2017-10-03"})]),
            tags: %{"published" => "2011-01-01"}
          })
        )

      refute draft.work.published.approved
    end
  end

  describe "naming what gets created" do
    # The motivating case: "David Wong" is a pen name of Jason Pargin, and
    # importing it as a new author needed a new person under a DIFFERENT name.
    test "a credit's identity and its person can be named separately" do
      item = item(%{matches: matches([provider_candidate(%{"authors" => ["David Wong"]})])})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        item.draft
        |> Draft.Edit.rename_credit(:work, 0, "David Wong")
        |> Draft.Edit.set_person(:work, 0, 0, %{name: "Jason Pargin", person_id: nil})

      credit = hd(draft.work.authors)
      assert credit.name == "David Wong"
      assert [%{name: "Jason Pargin", person_id: nil}] = credit.people
      refute Credit.simple?(credit)
    end

    test "the default person follows the credit's name until it is customised" do
      item = item(%{matches: matches([provider_candidate(%{"authors" => ["Jmes S.A. Corey"]})])})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_credit(item.draft, :work, 0, "James S.A. Corey")

      # fixing a typo in the credited name shouldn't leave a person behind
      # still carrying it
      credit = hd(draft.work.authors)
      assert credit.name == "James S.A. Corey"
      assert [%{name: "James S.A. Corey"}] = credit.people
      assert Credit.simple?(credit)

      # but once the person is somebody else, renaming the credit leaves them
      # alone
      draft = Draft.Edit.set_person(draft, :work, 0, 0, %{name: "Ty Franck", person_id: nil})
      draft = Draft.Edit.rename_credit(draft, :work, 0, "J.S.A. Corey")

      assert [%{name: "Ty Franck"}] = hd(draft.work.authors).people
    end

    test "a half-typed name is storable but never resolved" do
      item = item(%{matches: matches([provider_candidate(%{})])})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_credit(item.draft, :work, 0, "")

      # clearing the box to retype must not fail the changeset — validation
      # gates saving, the invariant gates importing
      assert {:ok, saved} = Inbox.update_draft(item, Inbox.dump_draft(draft))
      assert hd(saved.draft.work.authors).name in [nil, ""]
      refute Credit.resolved?(hd(saved.draft.work.authors))
      refute hd(saved.draft.work.authors).approved
    end

    test "a created series can be renamed" do
      candidates = [
        provider_candidate(%{"series" => [%{"name" => "Expanse", "number" => "1"}]})
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_series(item.draft, 0, "The Expanse")

      assert hd(draft.work.series).name == "The Expanse"
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
