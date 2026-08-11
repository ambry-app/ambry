defmodule Ambry.Inbox.DraftTest do
  use Ambry.DataCase

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.InboxItem
  alias Ambry.Repo

  defp item(attrs) do
    %InboxItem{path: "/downloads/Some Release", files: ["/downloads/Some Release/book.m4b"]}
    |> Map.merge(attrs)
    |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))
  end

  # A settled name field, for the hand-built drafts below.
  defp named(value), do: %Field{value: value, source: "test", approved: true, required: true}

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

  defp recording_record(attrs) do
    Map.merge(
      %{
        "source" => "provider:audible",
        "provider_name" => "Audible",
        "id" => "B01",
        "title" => "Leviathan Wakes",
        "narrators" => ["Jefferson Mays"],
        "score" => 1.0
      },
      attrs
    )
  end

  # What a person-level provider's hit looks like in `matches["people"]`,
  # whether written by matching or by `Lookup.research_person/3`.
  defp person_evidence(attrs) do
    Map.merge(
      %{
        "source" => "provider:wikipedia",
        "provider_name" => "Wikipedia",
        "id" => "Q1",
        "name" => "Somebody",
        "images" => [],
        "description" => nil
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
      },
      "people" => Keyword.get(opts, :people, %{})
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

    # The recording level has refused to adopt a doubted match since it was
    # built; the work level ticked its top record whatever the score said, so a
    # weak match quietly supplied the title, date and authors of a book it
    # wasn't about. Fields that look settled and are wrong beat visibly empty
    # ones every time — which is why this is the one thing the removed
    # "confirm it's a new book" gate was really protecting.
    test "a doubted work match fills nothing in and says why" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5})
      ]

      draft = Seed.build(item(%{matches: matches(candidates, confidence: 0.5), tags: %{}}))

      assert draft.work.doubt == :low_confidence
      assert draft.work.doubt_detail =~ "Something Else"
      assert draft.work.sources == []
      # nothing was adopted, so the title is a decision rather than a wrong answer
      refute draft.work.title.value == "Something Else"
      assert Enum.any?(Draft.unresolved(draft), &(&1.label =~ "records describe this book"))
    end

    # The doubt asks "which records describe this book". Ticking one is the
    # answer, and it used to leave the doubt standing — so the decision stayed
    # outstanding forever and the item could never be imported, with no
    # control on the page able to clear it. The recording level has cleared
    # its own doubt on a tick since it was built; the work level was given
    # doubt later and this half was missed. Found by a real end-to-end import.
    test "ticking a record settles a doubted work" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5}),
        provider_candidate(%{"id" => "b", "title" => "The Real One", "score" => 0.45})
      ]

      item = item(%{matches: matches(candidates, confidence: 0.5), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert item.draft.work.doubt == :low_confidence
      assert Enum.any?(Draft.unresolved(item.draft), &(&1.label =~ "records describe this book"))

      ticked =
        Draft.Edit.toggle_source(item.draft, item, :work, Enum.at(candidates, 1))

      assert ticked.work.doubt == :none
      refute Enum.any?(Draft.unresolved(ticked), &(&1.label =~ "records describe this book"))

      # and un-ticking the last one puts the question back
      untangled = Draft.Edit.toggle_source(ticked, item, :work, Enum.at(candidates, 1))
      assert untangled.work.sources == []
    end

    # The seeder sets `chosen_key` too, so keying re-derivation on it froze
    # every auto-settled field against all later evidence. Measured end to end
    # on the operator's Becky Chambers file: the work is doubted, so at seed
    # time the only title on offer is the tags' shelf label and it settles —
    # and then ticking the correct record could not dislodge it. The book
    # imported as "Wayfarers, Book 1" with the real title sitting un-chosen in
    # its own candidate list.
    test "a value the seeder settled follows a record the operator ticks" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5})
      ]

      item =
        item(%{
          matches: matches(candidates, confidence: 0.5),
          tags: %{"book_title" => "Shelf Label", "published" => "2011-06-15"}
        })

      {:ok, item} = Inbox.prepare_draft(item)

      # doubted, so nothing but the tags proposed a title and it settled
      assert item.draft.work.title.value == "Shelf Label"
      assert item.draft.work.title.approved
      refute item.draft.work.title.curated

      ticked = Draft.Edit.toggle_source(item.draft, item, :work, hd(candidates))

      # The record and the tags now disagree, so it becomes an open question
      # with both on offer — rather than staying silently stuck on the label.
      refute ticked.work.title.approved

      # the file's own name rides along as an advisory chip — offered, and
      # not counted among the sources that disagree
      assert Enum.map(ticked.work.title.candidates, & &1.value) == [
               "Something Else",
               "Shelf Label",
               "Some Release"
             ]

      # and taking the leading suggestion takes the ticked record's, not the
      # file's, because records outrank tags in the candidate order
      assert Draft.Edit.approve_all(ticked).work.title.value == "Something Else"
    end

    # A key can legitimately disappear while the answer stays on offer: the
    # operator picks the release-name chip, then ticks a record whose title
    # turns out to be identical, so the advisory chip is dropped as a
    # duplicate of it. Looking the choice up by key alone found nothing and
    # silently threw it away — measured on the Chambers book, which went from
    # ready to "pick a title" in the middle of a batch import with nobody
    # having touched it.
    test "a chosen value survives its candidate key disappearing" do
      candidates = [provider_candidate(%{"title" => "The Long Way to a Small, Angry Planet"})]

      item =
        %InboxItem{path: "/downloads/The Long Way to a Small, Angry Planet"}
        |> Map.merge(%{
          matches: matches(candidates, confidence: 0.5),
          tags: %{"book_title" => "Wayfarers, Book 1", "published" => "2014-01-01"}
        })
        |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))

      {:ok, item} = Inbox.prepare_draft(item)

      # doubted, so nothing is ticked and the file's name is on offer
      chosen = Draft.Edit.choose_field(item.draft, :work, :title, "release_name")
      assert chosen.work.title.value == "The Long Way to a Small, Angry Planet"
      assert chosen.work.title.curated

      # ticking the record makes its title identical, so the advisory chip is
      # dropped — the choice must survive on its value
      ticked = Draft.Edit.toggle_source(chosen, item, :work, hd(candidates))

      assert ticked.work.title.value == "The Long Way to a Small, Angry Planet"
      assert ticked.work.title.approved
      # and stays curated, or it would be movable by the next re-derivation
      assert ticked.work.title.curated
    end

    # The other half of the same rule: a chip a human picked must NOT move.
    test "a value the operator chose survives a record being ticked" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5}),
        provider_candidate(%{"id" => "b", "title" => "The Other One", "score" => 0.45})
      ]

      item =
        item(%{
          matches: matches(candidates, confidence: 0.5),
          tags: %{"book_title" => "Shelf Label", "published" => "2011-06-15"}
        })

      {:ok, item} = Inbox.prepare_draft(item)

      chosen = Draft.Edit.choose_field(item.draft, :work, :title, "tags")
      assert chosen.work.title.value == "Shelf Label"
      assert chosen.work.title.curated

      ticked = Draft.Edit.toggle_source(chosen, item, :work, hd(candidates))
      assert ticked.work.title.value == "Shelf Label"
    end

    test "a believed work match still adopts its records" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      assert draft.work.doubt == :none
      assert draft.work.sources != []
      assert draft.work.title.value == "Leviathan Wakes"
    end

    # "Is this a book you already have" is answered by the LOCAL search, and
    # nothing local matched. Gating it on how good the *provider* records are
    # conflated two questions and left the operator with an outstanding
    # decision whose only control lives in a block that renders solely when
    # there are local candidates to show — so there was nothing on the page to
    # settle it with.
    test "no local hit settles the identity as a new book" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Something Else", "score" => 0.5})
      ]

      draft = Seed.build(item(%{matches: matches(candidates, confidence: 0.5), tags: %{}}))

      assert draft.work.mode == :create
      assert draft.work.approved
      refute Enum.any?(Draft.unresolved(draft), &(&1.label =~ "already have"))
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
      assert [key] = credit.person_keys
      assert [person] = draft.people
      assert person.key == key
      assert person.person_id == nil
      assert Field.value(person.name) == "Nobody In This Library"
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

    # 3b's promise is that the operator never leaves the inbox to finish a
    # leaf entity, and a person with no face is unfinished. Matching asks
    # every person-level provider in the background, so the photo and the
    # biography are here to be proposed rather than fetched with somebody
    # waiting on them.
    test "a new person arrives with the photo and biography matching found" do
      candidates = [provider_candidate(%{"authors" => ["Travis Baldree"]})]

      draft =
        Seed.build(
          item(%{
            matches:
              matches(candidates,
                people: %{
                  "travis baldree" => %{
                    "name" => "Travis Baldree",
                    "candidates" => [
                      %{
                        "source" => "provider:hardcover",
                        "id" => "hc-9",
                        "name" => "Travis Baldree",
                        "images" => ["https://example.test/baldree.jpg"],
                        "description" => "An American author and audiobook narrator."
                      }
                    ]
                  }
                }
              ),
            tags: %{}
          })
        )

      assert [person] = draft.people
      assert Field.value(person.image) == "https://example.test/baldree.jpg"
      assert person.image.source == "provider:hardcover"
      assert Field.value(person.description) == "An American author and audiobook narrator."
      assert person.description.source == "provider:hardcover"
    end

    # An import with no photo is the previous behaviour, not a failure — and
    # every draft built before the people level existed has no such key.
    test "a person nothing was found for is still the plain proposal" do
      candidates = [provider_candidate(%{"authors" => ["Nobody In This Library"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [person] = draft.people
      assert Field.value(person.name) == "Nobody In This Library"
      assert Field.value(person.image) == nil
      assert Field.value(person.description) == nil
      # nothing to decide, so it doesn't become a question
      assert person.doubt == :nothing_found
      assert PersonDecision.resolved?(person)
    end

    # The databases disagree about the dots and spaces in "James S.A. Corey",
    # and none of those spellings is a different human. Deduping only
    # case-insensitively left one credit per spelling — two credits, two
    # person decisions, and a duplicate library author waiting at approval.
    test "two spellings of one author are one credit" do
      candidates = [
        provider_candidate(%{
          "id" => "rg",
          "source" => "provider:rreading_glasses",
          "provider_name" => "rreading-glasses",
          "authors" => ["James S.A. Corey"]
        }),
        provider_candidate(%{"id" => "hc", "authors" => ["James S. A. Corey"]})
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [credit] = draft.work.authors
      assert [_one_person] = draft.people
      assert [_one_key] = credit.person_keys
    end

    test "a punctuation variant of a name links the existing identity" do
      person = insert(:person, name: "James S. A. Corey")
      insert(:author, name: "James S. A. Corey", person: person)

      candidates = [provider_candidate(%{"authors" => ["James S.A. Corey"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [%{mode: :link} = credit] = draft.work.authors
      assert credit.identity_id
    end

    # The library's "Patricia Rodríguez" came from a record; the next file's
    # tags say "Patricia Rodriguez". One narrator — the accent was one
    # approval away from a second person of the same name.
    test "an accent variant of a name links the existing identity" do
      person = insert(:person, name: "Patricia Rodríguez")
      insert(:author, name: "Patricia Rodríguez", person: person)

      candidates = [provider_candidate(%{"authors" => ["Patricia Rodriguez"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [%{mode: :link} = credit] = draft.work.authors
      assert credit.identity_id
    end

    # Items matched before the person key became punctuation-insensitive
    # stored their evidence under the older spelling-sensitive keys; that
    # evidence must not go dark because the sameness rule improved.
    test "evidence stored under an older key still reaches the person" do
      candidates = [provider_candidate(%{"authors" => ["James S.A. Corey"]})]

      draft =
        Seed.build(
          item(%{
            matches:
              matches(candidates,
                people: %{
                  "james s. a. corey" => %{
                    "name" => "James S. A. Corey",
                    "candidates" => [
                      person_evidence(%{
                        "name" => "James S. A. Corey",
                        "images" => ["https://example.test/corey.jpg"]
                      })
                    ]
                  }
                }
              ),
            tags: %{}
          })
        )

      assert [person] = draft.people
      assert Field.value(person.image) == "https://example.test/corey.jpg"
    end

    test "two or more people behind one credit is just a longer list" do
      # the composite case, which needs no special pathway: one Author, two
      # People, expressed as two keys on the same credit
      credit = %Credit{
        name: "James S.A. Corey",
        kind: :author,
        mode: :create,
        approved: true,
        person_keys: ["daniel abraham", "ty franck"]
      }

      assert Credit.resolved?(credit)
      assert length(credit.person_keys) == 2
    end

    # Validation gates *saving*, the invariant gates *importing*. A half-made
    # credit has to be storable — otherwise the operator couldn't add a second
    # person and then name them — so only an approved one is rejected.
    test "a half-made credit saves; an approved one with nobody behind it does not" do
      in_progress =
        Credit.changeset(%Credit{}, %{
          name: "Somebody",
          kind: :author,
          mode: :create,
          person_keys: []
        })

      assert in_progress.valid?
      refute Credit.resolved?(Ecto.Changeset.apply_changes(in_progress))

      approved =
        Credit.changeset(%Credit{}, %{
          name: "Somebody",
          kind: :author,
          mode: :create,
          person_keys: [],
          approved: true
        })

      refute approved.valid?
      assert %{person_keys: ["needs at least one person behind it"]} = errors_on(approved)
    end

    # The credit is resolved; the *person* is the one still needing a name, and
    # that is reported once for the human rather than once per credit — which
    # is the whole reason people became their own level.
    test "a person nobody has named yet keeps the import unresolved" do
      draft = %Draft{
        work: %Draft.Work{
          mode: :create,
          approved: true,
          authors: [
            %Credit{
              name: "James S.A. Corey",
              kind: :author,
              mode: :create,
              approved: true,
              person_keys: ["daniel abraham", "unnamed"]
            }
          ]
        },
        people: [
          %PersonDecision{key: "daniel abraham", approved: true, name: named("Daniel Abraham")},
          %PersonDecision{key: "unnamed", approved: true, name: named(nil)}
        ]
      }

      assert Enum.any?(Draft.unresolved(draft), &(&1.section == :people and &1.state == :missing))
    end
  end

  # A credit auto-approves on the premise "nobody by that name at all", and a
  # sibling import can invalidate it: Joyland created the person Stephen
  # King, and Holly's narrator credit for him then sailed through approval
  # and created a second Stephen King. "Is this the same human?" is never
  # automated, so the sibling import reopens the question instead.
  describe "a sibling import that creates a person reopens the question" do
    test "an auto-approved credit for a person who now exists goes back to unapproved" do
      recording = [recording_record(%{"narrators" => ["Stephen King"]})]

      item =
        item(%{
          matches: matches([], recording: recording, recording_confidence: 0.9),
          tags: %{"book_title" => "Holly", "published" => "2023-09-05"}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      assert [%{approved: true}] = item.draft.recording.narrators

      insert(:person, name: "Stephen King")

      relinked = Seed.relink(item.draft, item)
      assert [%{approved: false}] = relinked.recording.narrators
    end

    test "answering the reopened question is final" do
      recording = [recording_record(%{"narrators" => ["Stephen King"]})]

      item =
        item(%{
          matches: matches([], recording: recording, recording_confidence: 0.9),
          tags: %{"book_title" => "Holly", "published" => "2023-09-05"}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      insert(:person, name: "Stephen King")

      answered =
        item.draft
        |> Seed.relink(item)
        |> Draft.Edit.approve_credit(:recording, 0, true)
        |> Seed.relink(item)

      assert [%{approved: true}] = answered.recording.narrators
    end
  end

  # "Bill Hodges" and "Bill Hodges Trilogy" are one series spelled two ways,
  # and a real batch filed End of Watch under both — plus "Phèdre's Trilogy"
  # as an accent variant of "Kushiel's Legacy: Phedre Trilogy". Same family
  # as titles and people: fillers, punctuation, accents and subtitle heads
  # are spellings, not different series.
  describe "series spellings collapse" do
    test "a filler-word variant is one series membership" do
      candidates = [
        provider_candidate(%{
          "id" => "a",
          "series" => [%{"name" => "Bill Hodges", "number" => "3"}]
        }),
        provider_candidate(%{
          "id" => "b",
          "series" => [%{"name" => "Bill Hodges Trilogy", "number" => "3"}]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [series] = draft.work.series
      assert to_string(series.number) == "3"
    end

    test "a filler-word variant links the series already in the library" do
      existing = insert(:series, name: "Bill Hodges")

      candidates = [
        provider_candidate(%{
          "series" => [%{"name" => "Bill Hodges Trilogy", "number" => "3"}]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [%{mode: :link, series_id: id}] = draft.work.series
      assert id == existing.id
    end
  end

  describe "junk series stay off the form" do
    # Goodreads-derived data models an author's whole bibliography as a
    # series named after them — Joyland arrived in a series called "Stephen
    # King", Un Lun Dun in one called "China Miéville", two of ten releases
    # in one real batch.
    test "a series named after a credited author is a shelf, not a series" do
      candidates = [
        provider_candidate(%{
          "authors" => ["Stephen King"],
          "series" => [
            %{"name" => "Stephen King", "number" => "37"},
            %{"name" => "The Hard Case Crime Series", "number" => "1"}
          ]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [series] = draft.work.series
      assert series.name == "The Hard Case Crime Series"
    end
  end

  describe "series numbers are never invented" do
    # `book_number` is a decimal column, so `SeriesLink` refuses a number that
    # won't cast — but the seeder proposed one anyway, which made the whole
    # draft changeset invalid. `RunMatch` then failed, retried and failed
    # again until Oban gave up, so the item never got a draft at all and
    # nothing in the app said why. Found importing the operator's own
    # `01 Wool [128k]`: rreading-glasses answers "1A" and Hardcover "1-5".
    test "a position that isn't a number never reaches the draft" do
      candidates = [
        provider_candidate(%{
          "series" => [
            %{"name" => "Silo", "number" => "1A"},
            %{"name" => "Wool", "number" => "1-5"},
            %{"name" => "The Expanse", "number" => "2"}
          ]
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})

      # the whole point: this used to be invalid and kill the match job
      assert {:ok, item} = Inbox.prepare_draft(item)

      numbers = Map.new(item.draft.work.series, &{&1.name, &1.number})
      assert numbers["Silo"] == nil
      assert numbers["Wool"] == nil
      assert numbers["The Expanse"] == "2"

      # the memberships survive; the missing numbers are ordinary questions
      assert Enum.any?(Draft.unresolved(item.draft), &(&1.label =~ "Series: Silo"))
    end

    test "a tag's unparseable number is dropped too" do
      item =
        item(%{
          matches: matches([provider_candidate(%{"series" => []})]),
          tags: %{"series" => "Silo", "series_number" => "1-5"}
        })

      assert {:ok, item} = Inbox.prepare_draft(item)
      assert [link] = item.draft.work.series
      assert link.number == nil
    end

    test "a series with no number anywhere stays unresolved" do
      candidates = [provider_candidate(%{"series" => ["The Expanse"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [link] = draft.work.series
      refute SeriesLink.resolved?(link)
      assert link.number == nil
      assert SeriesLink.state(link) == :missing
    end

    # `book_number` is a required column, so an approved-but-numberless
    # membership is not storable — approving it read as resolved and the
    # refusal surfaced at insert time as "Couldn't add this to the library."
    # (Memory's Legion, whose Expanse membership arrives unnumbered).
    test "approving a numberless membership does not settle it" do
      candidates = [provider_candidate(%{"series" => ["The Expanse"]})]
      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      draft = Ambry.Inbox.Draft.Edit.approve_series(draft, 0, true)

      assert [link] = draft.work.series
      assert link.approved
      refute SeriesLink.resolved?(link)
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
        provider_candidate(%{"series" => ["The Expanse", "Expanse Novellas"]})
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

    test "embedded art and a provider cover: the provider's is taken, both offered" do
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

      # Two cover URLs are two pictures nothing here can compare. Calling that
      # "sources disagree" made the operator arbitrate a non-question on every
      # import with embedded art — so the provider's is taken and the file's
      # own stays one click away.
      assert draft.recording.cover.approved
      assert draft.recording.cover.value == "https://example.test/cover.jpg"
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
        provider_candidate(%{"id" => "hc-1", "published" => "2011-06-15"}),
        provider_candidate(%{
          "source" => "provider:rreading_glasses",
          "provider_name" => "rreading-glasses",
          "id" => "rg-1",
          "title" => "Something Else Entirely",
          "published" => "2012-01-20",
          "score" => 0.4
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      # only the top record is ticked to begin with
      assert length(item.draft.work.sources) == 1

      draft = Draft.Edit.toggle_source(item.draft, item, :work, Enum.at(candidates, 1))

      assert length(draft.work.sources) == 2
      values = Enum.map(draft.work.published.candidates, & &1.value)
      assert "2011-06-15" in values
      assert "2012-01-20" in values
    end

    test "un-ticking a record takes its values back out" do
      candidates = [provider_candidate(%{"published" => "2011-06-15"})]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert item.draft.work.published.value == "2011-06-15"

      draft = Draft.Edit.toggle_source(item.draft, item, :work, hd(candidates))

      assert draft.work.sources == []
      assert draft.work.published.candidates == []
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
        |> Draft.Edit.rename_person("davidwong", "Jason Pargin")
        |> Draft.Edit.approve_credit(:work, 0, true)

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      after_tick = Draft.Edit.toggle_source(item.draft, item, :recording, hd(recording))

      assert [credit] = after_tick.work.authors
      assert credit.name == "David Wong"
      assert [person] = Draft.people_for(after_tick, credit)
      assert Field.value(person.name) == "Jason Pargin"
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

    # A curated draft survives a re-match via resettle rather than a rebuild —
    # but the query is evidence, not a decision, and the evidence header kept
    # reporting the search from the draft's first seeding while the records
    # below it came from a newer one.
    test "a re-match's query reaches a resettled draft's evidence header" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_credit(item.draft, :work, 0, "Somebody Else")
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      item =
        update_in(
          item.matches["work"],
          &Map.merge(&1, %{
            "query" => "a plainer title",
            "query_fields" => %{"title" => "a plainer title"}
          })
        )

      reseeded = Draft.Edit.resettle(item.draft, item)

      assert reseeded.work.query == "a plainer title"
      assert reseeded.work.query_fields == %{"title" => "a plainer title"}
    end
  end

  # `Draft.curated?/1` decides whether a re-match rebuilds the draft or
  # re-derives around the operator. It only looked at fields, credits, series
  # and people — so a draft whose only human input was ticking records or
  # answering the identity question was rebuilt wholesale, discarding exactly
  # the decisions the tick and the answer were.
  describe "ticking records and answering identity count as curation" do
    test "a freshly seeded draft is not curated" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      refute Draft.curated?(item.draft)
    end

    test "ticking a work record marks the draft curated" do
      record = provider_candidate(%{"score" => 0.5})
      item = item(%{matches: matches([record], confidence: 0.3), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      refute Draft.curated?(item.draft)

      draft = Draft.Edit.toggle_source(item.draft, item, :work, record)

      assert Draft.curated?(draft)
    end

    test "ticking a recording record marks the draft curated" do
      record = recording_record(%{"score" => 0.5})

      item =
        item(%{
          matches: matches([], recording: [record], recording_confidence: 0.3),
          tags: %{}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      refute Draft.curated?(item.draft)

      draft = Draft.Edit.toggle_source(item.draft, item, :recording, record)

      assert Draft.curated?(draft)
    end

    test "answering the identity question marks the draft curated" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      refute Draft.curated?(item.draft)

      assert Draft.curated?(Draft.Edit.new_book(item.draft, item))
    end

    test "settling the recording as uncatalogued marks the draft curated" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      refute Draft.curated?(item.draft)

      assert Draft.curated?(Draft.Edit.uncatalogued(item.draft, item))
    end

    test "the badge state follows decisions, not match history" do
      record = provider_candidate(%{"score" => 0.5})
      item = item(%{matches: matches([record], confidence: 0.3), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert Draft.level_state(item.draft.work) == :unsure
      assert Draft.level_state(item.draft.recording) == :no_match

      # ticking the doubted record is "yes, you were right"
      draft = Draft.Edit.toggle_source(item.draft, item, :work, record)
      assert Draft.level_state(draft.work) == :confirmed
    end

    test "a believed match reads trusted until a human touches it" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert Draft.level_state(item.draft.work) == :trusted
    end

    # Clicking the already-ticked record UNTICKS it, so "yes, you were right"
    # used to cost an untick and a re-tick with a reseed churning each way.
    test "confirm approves the machine's ticks without moving them" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      ticked = item.draft.work.sources

      draft = Draft.Edit.confirm_level(item.draft, :work)

      assert Draft.level_state(draft.work) == :confirmed
      assert draft.work.sources == ticked
      assert Draft.curated?(draft)
    end

    test "the tick survives the reseed it triggers" do
      record = provider_candidate(%{"score" => 0.5})
      item = item(%{matches: matches([record], confidence: 0.3), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.toggle_source(item.draft, item, :work, record)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert Draft.curated?(Draft.Edit.resettle(item.draft, item))
    end
  end

  # Removal used to be a bare List.delete_at — the one edit that didn't
  # stick (keep_curated re-appended the fresh proposal on the next reseed)
  # and the one with no way back. It is a tombstone now.
  describe "removing a row is a decision" do
    defp series_item do
      candidates = [
        provider_candidate(%{
          "series" => [%{"name" => "The Expanse", "number" => "1"}]
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      item
    end

    test "a removed series does not resurrect on reseed" do
      item = series_item()
      assert [%{name: "The Expanse"}] = item.draft.work.series

      draft = Draft.Edit.remove_series(item.draft, 0)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      reseeded = Draft.Edit.resettle(item.draft, item)

      assert [%{name: "The Expanse", removed: true}] = reseeded.work.series
    end

    test "a removed series stops blocking the import" do
      item = series_item()

      draft = Draft.Edit.remove_series(item.draft, 0)

      refute Enum.any?(Draft.unresolved(draft), &(&1.label =~ "Series"))
    end

    test "restore brings the series back exactly as it was" do
      item = series_item()

      draft =
        item.draft
        |> Draft.Edit.remove_series(0)
        |> Draft.Edit.restore_series(0)

      assert [%{name: "The Expanse", number: "1", removed: false}] = draft.work.series
    end

    test "a removed credit drops its person and restore re-mints them" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      assert [%{name: "James S.A. Corey"}] = item.draft.work.authors
      assert [_person] = item.draft.people

      removed = Draft.Edit.remove_credit(item.draft, item, :work, 0)

      # the person only this credit referenced is nobody's decision now —
      # it used to linger and block the import invisibly
      assert removed.people == []
      refute Enum.any?(Draft.unresolved(removed), &(&1.label =~ "Person"))

      restored = Draft.Edit.restore_credit(removed, item, :work, 0)

      assert [%{name: "James S.A. Corey", removed: false}] = restored.work.authors
      assert [_person] = restored.people
    end

    test "a removed credit never reaches approval params" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.remove_credit(item.draft, item, :work, 0)

      # approve-all must not quietly re-arm the tombstone
      approved = Draft.Edit.approve_all(draft)
      assert [%{removed: true}] = approved.work.authors
    end
  end

  # Proposals must always be recoverable: the scalar fields keep theirs as
  # candidates, but a credit's or series' name was a plain string — cleared
  # once, the provider's spelling was gone with nothing on screen holding it.
  describe "the evidence's spelling stays reachable" do
    test "a renamed series can be reset to what the records proposed" do
      item = series_item()

      draft =
        item.draft
        |> Draft.Edit.rename_series(0, "The Expans")
        |> Draft.Edit.reset_series_name(0)

      assert [%{name: "The Expanse", curated: true}] = draft.work.series
    end

    test "a renamed credit can be reset, and its tracking person follows" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        item.draft
        |> Draft.Edit.rename_credit(:work, 0, "")
        |> Draft.Edit.reset_credit_name(:work, 0)

      assert [%{name: "James S.A. Corey", proposed_name: "James S.A. Corey"}] =
               draft.work.authors

      assert [person] = draft.people
      assert Field.value(person.name) == "James S.A. Corey"
    end

    test "a manually edited scalar keeps collecting fresh candidates" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      # type over the title — the field is the operator's now
      edited = update_in(item.draft.work.title, &Field.edit(&1, "My Own Title")).draft
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(edited))

      reseeded = Draft.Edit.resettle(item.draft, item)

      # the value is pinned, but the evidence still flows: the proposal
      # remains on offer as a chip instead of being frozen out forever
      assert Field.value(reseeded.work.title) == "My Own Title"
      assert Enum.any?(reseeded.work.title.candidates, &(&1.value == "Leviathan Wakes"))
    end
  end

  describe "rows the sources didn't propose" do
    test "an added author mints its person once it is named" do
      item = item(%{matches: matches([]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.work.authors == []

      draft = Draft.Edit.add_credit(item.draft, :work)

      assert [%{name: "", curated: true, approved: false, person_keys: []}] =
               draft.work.authors

      draft =
        draft
        |> Draft.Edit.rename_credit(:work, 0, "Martha Wells")
        |> Draft.Edit.sync_people(item)

      assert [%{name: "Martha Wells", person_keys: [key]}] = draft.work.authors
      assert [%{key: ^key} = person] = draft.people
      assert Field.value(person.name) == "Martha Wells"
    end

    test "a manually added row really deletes — nothing proposed it" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        item.draft
        |> Draft.Edit.add_series()
        |> Draft.Edit.rename_series(0, "Not A Real Series")
        |> Draft.Edit.remove_series(0)

      assert draft.work.series == []

      draft =
        draft
        |> Draft.Edit.add_credit(:work)
        |> Draft.Edit.rename_credit(:work, 1, "Nobody Real")
        |> Draft.Edit.sync_people(item)
        |> Draft.Edit.remove_credit(item, :work, 1)

      # gone entirely, and the person it minted goes with it
      assert [%{source: "provider:hardcover"}] = draft.work.authors
      refute Enum.any?(draft.people, &(Field.value(&1.name) == "Nobody Real"))
    end

    test "an added series survives reseeds like any curated row" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        item.draft
        |> Draft.Edit.add_series()
        |> Draft.Edit.rename_series(0, "The Murderbot Diaries")
        |> Draft.Edit.set_series_number(0, "1")

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      reseeded = Draft.Edit.resettle(item.draft, item)

      assert Enum.any?(reseeded.work.series, &(&1.name == "The Murderbot Diaries"))
    end
  end

  # The reported flow: the operator reveals a pen name, renames the person
  # behind it (which marks them curated), and clicks "look again". The results
  # land in `matches` — and a reseed that skipped curated people wholesale
  # showed nothing new for exactly the people the button exists for.
  describe "a re-search reaches a curated person" do
    test "a renamed person drops the old face and picks up what a re-search finds" do
      work = [provider_candidate(%{"authors" => ["James S.A. Corey"]})]

      item =
        item(%{
          matches:
            matches(work,
              people: %{
                "james s.a. corey" => %{
                  "name" => "James S.A. Corey",
                  "candidates" => [
                    person_evidence(%{
                      "id" => "corey",
                      "name" => "James S.A. Corey",
                      "images" => ["https://example.test/corey.jpg"]
                    })
                  ]
                }
              }
            ),
          tags: %{}
        })

      {:ok, item} = Inbox.prepare_draft(item)

      # the pen name's own photo arrived with the item
      assert [person] = item.draft.people
      assert Field.value(person.image) == "https://example.test/corey.jpg"

      draft = Draft.Edit.rename_person(item.draft, person.key, "Daniel Abraham")
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      # nobody has searched the new name yet: the pen name's face stops being
      # offered rather than posing as evidence about Daniel Abraham, and the
      # doubt says looking again is what would help
      reseeded = Draft.Edit.resettle(item.draft, item)
      assert [person] = reseeded.people
      assert Field.value(person.name) == "Daniel Abraham"
      assert person.image.candidates == []
      assert person.doubt == :low_confidence

      # "look again" adds evidence about the new name — added, never
      # replaced, exactly as Lookup.research_person writes it
      item =
        update_in(item.matches["people"]["james s.a. corey"], fn held ->
          held
          |> Map.put("name", "Daniel Abraham")
          |> Map.update!(
            "candidates",
            &(&1 ++
                [
                  person_evidence(%{
                    "id" => "abraham",
                    "name" => "Daniel Abraham",
                    "images" => ["https://example.test/abraham.jpg"],
                    "description" => "An American author."
                  })
                ])
          )
        end)

      reseeded = Draft.Edit.resettle(item.draft, item)
      assert [person] = reseeded.people

      # the new evidence is on the form, and the typed name stays the
      # operator's
      assert Field.value(person.image) == "https://example.test/abraham.jpg"
      assert Field.value(person.description) == "An American author."
      assert Field.value(person.name) == "Daniel Abraham"
      assert person.name.source == "manual"
      assert person.doubt == :none
    end

    test "a person added to a credit gets their search results once named" do
      work = [provider_candidate(%{"authors" => ["James S.A. Corey"]})]
      item = item(%{matches: matches(work), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      # the operator adds the second half of the pen name and names them
      draft = Draft.Edit.add_person(item.draft, item, :work, 0)
      assert [_first, key] = hd(draft.work.authors).person_keys
      draft = Draft.Edit.rename_person(draft, key, "Ty Franck")
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      # "find a photo and bio" writes under the minted key
      item =
        update_in(item.matches["people"], fn people ->
          Map.put(people || %{}, key, %{
            "name" => "Ty Franck",
            "candidates" => [
              person_evidence(%{
                "id" => "franck",
                "name" => "Ty Franck",
                "images" => ["https://example.test/franck.jpg"],
                "description" => "An American writer."
              })
            ]
          })
        end)

      reseeded = Draft.Edit.resettle(item.draft, item)
      person = Enum.find(reseeded.people, &(&1.key == key))

      assert Field.value(person.image) == "https://example.test/franck.jpg"
      assert Field.value(person.description) == "An American writer."
      assert Field.value(person.name) == "Ty Franck"
      assert person.doubt == :none
    end

    # Picking a photo curates the *field*, not the person — and a picked photo
    # moving because some record got ticked is the same broken rule at a
    # different level.
    test "a picked photo survives re-derivation" do
      work = [provider_candidate(%{"authors" => ["Travis Baldree"]})]

      item =
        item(%{
          matches:
            matches(work,
              people: %{
                "travis baldree" => %{
                  "name" => "Travis Baldree",
                  "candidates" => [
                    person_evidence(%{
                      "id" => "tb-1",
                      "name" => "Travis Baldree",
                      "images" => ["https://example.test/first.jpg"]
                    }),
                    person_evidence(%{
                      "id" => "tb-2",
                      "name" => "Travis Baldree",
                      "images" => ["https://example.test/second.jpg"]
                    })
                  ]
                }
              }
            ),
          tags: %{}
        })

      {:ok, item} = Inbox.prepare_draft(item)

      # auto-settled on the first; the operator picks the second
      assert [person] = item.draft.people
      assert Field.value(person.image) == "https://example.test/first.jpg"

      second =
        Enum.find(person.image.candidates, &(&1.value == "https://example.test/second.jpg"))

      draft = Draft.Edit.choose_person_image(item.draft, "travisbaldree", second.key)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      reseeded = Draft.Edit.resettle(item.draft, item)
      assert [person] = reseeded.people
      assert Field.value(person.image) == "https://example.test/second.jpg"
      assert person.image.curated
    end
  end

  # Measured on the operator's real library: the tag title and the release
  # name disagree on 105 of 198 releases, and neither is reliably the better
  # one — the Wayfarers books are tagged "Wayfarers, Book 1" and named "The
  # Long Way to a Small, Angry Planet", while The Wild Robot's release name
  # yields "Peter Brown" and "Out of Spite, Out of Mind: Magic 2.0, Book 5"
  # truncates to "Out of Spite". So the name is *offered*, never preferred.
  # `Title: Series, Book N` is the dominant real-world tag shape, and scored
  # as a rival to the catalogue's bare title it asked "pick a title" on three
  # of seven books in one real batch — always for the same mechanical reason.
  describe "a subtitle is not a different title" do
    test "the tag's subtitle collapses into the record's bare title" do
      candidates = [provider_candidate(%{"title" => "Battle Ground"})]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"book_title" => "Battle Ground: The Dresden Files, Book 17"}
          })
        )

      # one answer, settled, and the bare title is the one kept
      assert draft.work.title.value == "Battle Ground"
      assert draft.work.title.approved
    end

    test "a dash separates a subtitle too" do
      candidates = [provider_candidate(%{"title" => "A Prayer for the Crown-Shy"})]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"book_title" => "A Prayer for the Crown-Shy - 01"}
          })
        )

      assert draft.work.title.value == "A Prayer for the Crown-Shy"
      assert draft.work.title.approved
    end

    # The subtlety this rule exists to survive: comparing the head on BOTH
    # sides would merge two different books that share a series prefix.
    test "two books sharing a prefix still disagree" do
      candidates = [provider_candidate(%{"title" => "The Expanse: Caliban's War"})]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"book_title" => "The Expanse: Leviathan Wakes"}
          })
        )

      refute draft.work.title.approved
      # both survive as rival answers (plus the advisory release-name chip)
      assert "The Expanse: Caliban's War" in Enum.map(draft.work.title.candidates, & &1.value)
      assert "The Expanse: Leviathan Wakes" in Enum.map(draft.work.title.candidates, & &1.value)
    end

    # A tag lowercases what a catalogue capitalizes, and drops the article
    # too. One answer written two ways — and the catalogue's spelling is the
    # title as written, so prefer-shorter must not pick the lowercase one.
    test "a leading article and casing are one title, spelled the catalogue's way" do
      candidates = [provider_candidate(%{"title" => "The House in the Cerulean Sea"})]

      draft =
        Seed.build(
          item(%{
            matches: matches(candidates),
            tags: %{"book_title" => "house in the cerulean sea"}
          })
        )

      assert draft.work.title.value == "The House in the Cerulean Sea"
      assert draft.work.title.approved
    end

    # The caps tie-break briefly preferred "Artemis (Unabridged)" over
    # "Artemis" — the parenthetical adds a capital. The junk-free spelling
    # wins first, always.
    test "the junk-free spelling wins the collapse" do
      candidates = [provider_candidate(%{"title" => "Artemis"})]

      draft =
        Seed.build(
          item(%{matches: matches(candidates), tags: %{"book_title" => "Artemis (Unabridged)"}})
        )

      assert draft.work.title.value == "Artemis"
      assert draft.work.title.approved
    end

    # Hardcover writes "Demon World Boba Shop:, Vol. 1" (their punctuation)
    # where rreading-glasses writes the bare title; offered as rivals, the
    # operator arbitrated a non-question.
    test "a labelled trailing ordinal folds into the bare title" do
      candidates = [
        provider_candidate(%{"id" => "a", "title" => "Demon World Boba Shop"}),
        provider_candidate(%{"id" => "b", "title" => "Demon World Boba Shop:, Vol. 1"})
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert draft.work.title.value == "Demon World Boba Shop"
      assert draft.work.title.approved
    end

    # A subtitle is punctuated. Plain word-prefix containment would merge
    # these, and they are two different books.
    test "a longer title that merely starts the same is not a subtitle" do
      candidates = [provider_candidate(%{"title" => "Dune Messiah"})]

      draft =
        Seed.build(item(%{matches: matches(candidates), tags: %{"book_title" => "Dune"}}))

      refute draft.work.title.approved
      assert "Dune" in Enum.map(draft.work.title.candidates, & &1.value)
      assert "Dune Messiah" in Enum.map(draft.work.title.candidates, & &1.value)
    end
  end

  describe "the file's own name is a proposal, not a rival" do
    test "it is offered as a chip without making the field a question" do
      item =
        %InboxItem{path: "/downloads/The Long Way to a Small, Angry Planet"}
        |> Map.merge(%{
          matches: matches([]),
          tags: %{"book_title" => "Wayfarers, Book 1", "published" => "2014-01-01"}
        })
        |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))

      draft = Seed.build(item)

      # settled on the tags, exactly as before — the name did not argue
      assert draft.work.title.value == "Wayfarers, Book 1"
      assert draft.work.title.approved

      # but the right answer is on the form, one click away
      assert %{value: "The Long Way to a Small, Angry Planet", source: "release_name"} =
               Enum.find(draft.work.title.candidates, &(&1.source == "release_name"))
    end

    # The old `fallback:` behaviour, kept: with nothing else on offer the name
    # stops being advisory and answers the question.
    test "it settles the field when nothing else proposed anything" do
      item =
        %InboxItem{path: "/downloads/Leviathan Wakes"}
        |> Map.merge(%{matches: matches([]), tags: %{"published" => "2011-06-15"}})
        |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))

      draft = Seed.build(item)

      assert draft.work.title.value == "Leviathan Wakes"
      assert draft.work.title.approved
    end

    test "it is not repeated as a second chip when it agrees" do
      item =
        %InboxItem{path: "/downloads/Leviathan Wakes"}
        |> Map.merge(%{
          matches: matches([provider_candidate(%{})]),
          tags: %{"book_title" => "Leviathan Wakes"}
        })
        |> then(&(%InboxItem{} |> InboxItem.changeset(Map.from_struct(&1)) |> Repo.insert!()))

      draft = Seed.build(item)

      refute Enum.any?(draft.work.title.candidates, &(&1.source == "release_name"))
      assert draft.work.title.approved
    end
  end

  describe "choosing between chips" do
    # A settled field is one somebody already answered; its chip has to look
    # answered, or the form says "sources disagree" in green and nothing else.
    test "an auto-settled field arrives with its chip already chosen" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      assert draft.work.title.approved

      # the record's proposal is the one taken; the file's own name rides
      # along as an advisory chip that never argued
      assert [chip, advisory] = draft.work.title.candidates
      assert Draft.Field.chose?(draft.work.title, chip)
      assert chip.source == "provider:hardcover"
      assert advisory.source == "release_name"
      refute Draft.Field.chose?(draft.work.title, advisory)
    end

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

  # The display format says how much of the date is real, so it is never a
  # question the operator should be left holding while the date beside it is
  # settled. It was matched to the date by *source*, which two records from one
  # provider make ambiguous and which collapsing agreeing proposals makes
  # unfindable — so the rule routinely did nothing at all.
  describe "the date's display format" do
    test "settles as full when the settled date can only be a full one" do
      # the reported bug: the records disagree about the format, so the field
      # was left reported as undecided beside a date that had plainly already
      # decided it — October 3rd is not a year in disguise
      candidates = [
        provider_candidate(%{
          "id" => "a",
          "published" => "2017-10-03",
          "published_format" => "year"
        }),
        provider_candidate(%{
          "source" => "provider:rreading_glasses",
          "id" => "rg-1",
          "published" => "2017-10-03",
          "published_format" => "full",
          "score" => 0.94
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert draft.work.published.value == "2017-10-03"
      assert draft.work.published_format.value == "full"
      assert draft.work.published_format.approved
    end

    test "takes the winning record's format when the date lands on a 1st" do
      # year-only knowledge arrives as a literal Jan 1st and month-only as the
      # 1st of the month, so a date on a 1st really is undecidable by itself
      # and the derivation must not overrule the record that proposed it
      candidates = [
        provider_candidate(%{
          "id" => "a",
          "published" => "2017-01-01",
          "published_format" => "year"
        }),
        provider_candidate(%{
          "source" => "provider:rreading_glasses",
          "id" => "rg-1",
          "published" => "2017-01-01",
          "published_format" => "full",
          "score" => 0.94
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert draft.work.published.value == "2017-01-01"
      assert draft.work.published_format.value == "year"
    end

    # Measured on a real import (Legends & Lattes): Hardcover and the file's
    # tags both said 2022-01-01, and the merged chip was credited to the tags —
    # so the form said "from the file's tags" about a value a provider had
    # corroborated, and approval wrote that as provenance. `prefer` returns a
    # value, which cannot break a tie between two candidates proposing the same
    # one, and comparing its answer to `incoming.value` called every tie for
    # whoever came last.
    test "a value two sources agree on is credited to the provider, not the tags" do
      item =
        item(%{
          matches: matches([provider_candidate(%{"published" => "2022-01-01"})]),
          tags: %{"published" => "2022-01-01", "published_format" => "year"}
        })

      draft = Seed.build(item)

      assert [chip] = draft.work.published.candidates
      assert chip.source == "provider:hardcover"
      assert draft.work.published.source == "provider:hardcover"
      # and both are still credited on the chip
      assert chip.label =~ "Hardcover"
      assert chip.label =~ "tags"
    end

    test "an auto-settled format highlights the chip it took" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      assert [chip] = draft.work.published_format.candidates
      assert Draft.Field.chose?(draft.work.published_format, chip)
    end

    test "follows a date the operator picks by hand" do
      # two years apart, so the date can't settle itself and the operator has
      # to choose — at which point the format has to follow, and only the
      # seeder knew how to do that
      candidates = [
        provider_candidate(%{
          "id" => "a",
          "published" => "2016-01-01",
          "published_format" => "year"
        }),
        provider_candidate(%{
          "id" => "b",
          "published" => "2017-10-03",
          "published_format" => "full",
          "score" => 0.94
        })
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      refute item.draft.work.published.approved

      [_first, second] = item.draft.work.published.candidates
      draft = Draft.Edit.choose_field(item.draft, :work, :published, second.key)
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert item.draft.work.published.value == "2017-10-03"
      assert item.draft.work.published_format.value == "full"
      assert item.draft.work.published_format.approved
    end

    # Nobody records June 2nd to mean "2011". The format had already settled
    # as year (from a year-only tag date), and the settled-format guard then
    # left a full-precision typed date rendering as a bare year — measured on
    # the operator's Leviathan Wakes.
    test "a typed full date overrides a settled year format" do
      item =
        item(%{
          matches: matches([]),
          tags: %{
            "book_title" => "Leviathan Wakes",
            "published" => "2011-01-01",
            "published_format" => "year"
          }
        })

      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.work.published_format.value == "year"

      draft = item.draft
      draft = put_in(draft.work.published, Field.edit(draft.work.published, "2011-06-02"))
      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert item.draft.work.published.value == "2011-06-02"
      assert item.draft.work.published_format.value == "full"
    end

    # The work side had the aligner and the recording side didn't, so typing
    # a release date by hand settled one half of a two-column fact.
    test "the recording's format follows its date too" do
      recording = [recording_record(%{"published" => "2019-01-01", "published_format" => "year"})]

      item =
        item(%{
          matches: matches([], recording: recording, recording_confidence: 0.9),
          tags: %{"book_title" => "Leviathan Wakes", "published" => "2011-01-01"}
        })

      {:ok, item} = Inbox.prepare_draft(item)
      assert item.draft.recording.published_format.value == "year"

      draft = item.draft

      draft =
        put_in(draft.recording.published, Field.edit(draft.recording.published, "2019-08-06"))

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert item.draft.recording.published.value == "2019-08-06"
      assert item.draft.recording.published_format.value == "full"
    end

    test "never overrules a format the operator settled themselves" do
      candidates = [
        provider_candidate(%{"published" => "2017-10-03", "published_format" => "full"})
      ]

      item = item(%{matches: matches(candidates), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        update_in(
          item.draft,
          [Access.key(:work), Access.key(:published_format)],
          &Draft.Field.edit(&1, "year")
        )

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(draft))

      assert item.draft.work.published_format.value == "year"
      assert item.draft.work.published_format.source == "manual"
    end
  end

  describe "mixing sources" do
    # Two databases agreeing on WHICH recording this is do not agree on
    # everything about it. Collapsing them to a winner left the operator
    # choosing between one provider and the file's tags.
    test "a corroborating provider still gets to propose its own values" do
      recording = [
        recording_record(%{"id" => "B01", "publisher" => "Audible Studios"}),
        recording_record(%{
          "source" => "provider:hardcover",
          "provider_name" => "Hardcover editions",
          "id" => "ed-1",
          "publisher" => "Recorded Books",
          "score" => 0.99
        })
      ]

      draft =
        Seed.build(
          item(%{
            matches:
              matches([provider_candidate(%{})], recording: recording, recording_confidence: 1.0),
            tags: %{}
          })
        )

      publishers = Enum.map(draft.recording.publisher.candidates, & &1.value)
      assert "Audible Studios" in publishers
      assert "Recorded Books" in publishers
      # two audio publishers IS a real disagreement, unlike a description
      refute draft.recording.publisher.approved
    end

    # `publisher` on a recording means who is responsible for the *audiobook*
    # — Audible Studios, Graphic Audio, Soundbooth Theater. A work record's
    # publisher is whoever printed the book: a different company answering a
    # different question. Same for the description, which on an audio edition
    # carries the performance and the narrator, and for the cover, which is a
    # portrait print jacket.
    test "a work record never describes the recording" do
      work = [
        provider_candidate(%{
          "publisher" => "Orbit",
          "description" => "The print blurb",
          "cover_url" => "https://example.test/print-jacket.jpg"
        })
      ]

      recording = [recording_record(%{"publisher" => "Recorded Books"})]

      draft =
        Seed.build(
          item(%{
            matches: matches(work, recording: recording, recording_confidence: 1.0),
            tags: %{}
          })
        )

      assert draft.recording.publisher.value == "Recorded Books"
      refute "Orbit" in Enum.map(draft.recording.publisher.candidates, & &1.value)
      refute "The print blurb" in Enum.map(draft.recording.description.candidates, & &1.value)

      refute "https://example.test/print-jacket.jpg" in Enum.map(
               draft.recording.cover.candidates,
               & &1.value
             )
    end

    # A work-level record's date is the work's ORIGINAL publication date,
    # which is a different fact wearing the same name.
    test "the work's date is never offered as the recording's release date" do
      recording = [recording_record(%{"published" => "2011-06-15"})]

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

    # Two databases never write the same description, so treating them as
    # rival claims made this ambiguous on essentially every import.
    test "descriptions are alternatives, not a disagreement" do
      recording = [
        recording_record(%{"id" => "B01", "description" => "Audible's blurb"}),
        recording_record(%{
          "source" => "provider:hardcover",
          "id" => "ed-1",
          "description" => "Hardcover's blurb",
          "score" => 0.99
        })
      ]

      draft =
        Seed.build(
          item(%{
            matches:
              matches([provider_candidate(%{})], recording: recording, recording_confidence: 1.0),
            tags: %{"description" => "the file's own blurb"}
          })
        )

      assert draft.recording.description.approved
      assert draft.recording.description.value == "Audible's blurb"
      # and the others stay one click away
      assert length(draft.recording.description.candidates) == 3
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
        |> Draft.Edit.rename_person("davidwong", "Jason Pargin")

      credit = hd(draft.work.authors)
      assert credit.name == "David Wong"
      assert [person] = Draft.people_for(draft, credit)
      assert Field.value(person.name) == "Jason Pargin"
      assert person.person_id == nil
    end

    test "the default person follows the credit's name until it is customised" do
      item = item(%{matches: matches([provider_candidate(%{"authors" => ["Jmes S.A. Corey"]})])})
      {:ok, item} = Inbox.prepare_draft(item)

      draft = Draft.Edit.rename_credit(item.draft, :work, 0, "James S.A. Corey")

      # fixing a typo in the credited name shouldn't leave a person behind
      # still carrying it
      credit = hd(draft.work.authors)
      assert credit.name == "James S.A. Corey"
      assert [person] = Draft.people_for(draft, credit)
      assert Field.value(person.name) == "James S.A. Corey"
      assert Credit.simple?(credit)

      # but once the person is somebody else, renaming the credit leaves them
      # alone
      [person_key] = credit.person_keys
      draft = Draft.Edit.rename_person(draft, person_key, "Ty Franck")
      draft = Draft.Edit.rename_credit(draft, :work, 0, "J.S.A. Corey")

      assert [person] = Draft.people_for(draft, hd(draft.work.authors))
      assert Field.value(person.name) == "Ty Franck"
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

  describe "the group link" do
    # The series doctrine one level down: a part number is never invented,
    # and "part of this set, position unknown" stays a question.
    test "resolved?/1 and state/1" do
      refute GroupLink.resolved?(%GroupLink{part_number: nil, approved: true, name: "Set"})
      assert GroupLink.state(%GroupLink{part_number: nil}) == :missing

      unapproved = %GroupLink{part_number: 1, name: "Set", mode: :create}
      refute GroupLink.resolved?(unapproved)
      assert GroupLink.state(unapproved) == :unconfirmed

      # a blank name is storable (clearing to retype) but never resolved
      refute GroupLink.resolved?(%GroupLink{
               part_number: 1,
               approved: true,
               mode: :create,
               name: " "
             })

      refute GroupLink.resolved?(%GroupLink{part_number: 1, approved: true, mode: :link})

      assert GroupLink.resolved?(%GroupLink{
               part_number: 1,
               approved: true,
               mode: :create,
               name: "Set"
             })

      assert GroupLink.resolved?(%GroupLink{
               part_number: 2,
               approved: true,
               mode: :link,
               recording_group_id: 7
             })
    end

    test "a live unresolved link blocks import; removed or absent does not" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      absent = Draft.unresolved(draft)
      refute Enum.any?(absent, &(&1.label =~ "Part of a set"))

      live = put_in(draft, [Access.key(:recording), Access.key(:recording_group)], %GroupLink{})
      assert Enum.any?(Draft.unresolved(live), &(&1.label =~ "Part of a set"))

      removed = Draft.Edit.remove_group(live)
      refute Enum.any?(Draft.unresolved(removed), &(&1.label =~ "Part of a set"))
    end

    test "a proposal tombstones on removal and survives the dump/load round-trip" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      draft =
        put_in(item.draft, [Access.key(:recording), Access.key(:recording_group)], %GroupLink{
          mode: :create,
          name: "GraphicAudio",
          proposed_name: "GraphicAudio",
          source: "name",
          part_number: 1,
          parts_total: 2
        })

      removed = Draft.Edit.remove_group(draft)
      assert removed.recording.recording_group.removed

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(removed))
      assert item.draft.recording.recording_group.removed
      assert item.draft.recording.recording_group.name == "GraphicAudio"

      restored = Draft.Edit.restore_group(item.draft)
      refute restored.recording.recording_group.removed
    end

    test "an operator-added link really deletes and nil round-trips" do
      item = item(%{matches: matches([provider_candidate(%{})]), tags: %{}})
      {:ok, item} = Inbox.prepare_draft(item)

      added = Draft.Edit.add_group(item.draft)
      assert %GroupLink{source: "manual", curated: true} = added.recording.recording_group

      gone = Draft.Edit.remove_group(added)
      assert gone.recording.recording_group == nil

      {:ok, item} = Inbox.update_draft(item, Inbox.dump_draft(gone))
      assert item.draft.recording.recording_group == nil
    end

    test "approve_all settles a numbered link but never invents a part number" do
      draft = Seed.build(item(%{matches: matches([provider_candidate(%{})]), tags: %{}}))

      numbered =
        put_in(draft, [Access.key(:recording), Access.key(:recording_group)], %GroupLink{
          mode: :create,
          name: "Set",
          part_number: 1
        })

      settled = Draft.Edit.approve_all(numbered)
      assert settled.recording.recording_group.approved

      unnumbered =
        put_in(draft, [Access.key(:recording), Access.key(:recording_group)], %GroupLink{
          mode: :create,
          name: "Set",
          part_number: nil
        })

      still_open = Draft.Edit.approve_all(unnumbered)
      refute still_open.recording.recording_group.approved
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
            %{"name" => "Expanse Novellas", "number" => "2"}
          ]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [first, second] = draft.work.series
      assert first.number == "1"
      assert second.number == "2"
    end

    # Goodreads-derived data models "read these in story order" as a second
    # series sitting beside the real one. Seen repeatedly on the operator's
    # own library — Legends & Lattes arrives in both "Legends & Lattes" and
    # "Legends & Lattes (Chronological)" — and the form proposed them
    # identically, so one careless import creates a duplicate series with one
    # book in it that nobody will ever browse.
    test "a reader-created ordering is not proposed as a series" do
      candidates = [
        provider_candidate(%{
          "series" => [
            %{"name" => "Legends & Lattes", "number" => "1"},
            %{"name" => "Legends & Lattes (Chronological)", "number" => "2"}
          ]
        })
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert [link] = draft.work.series
      assert link.name == "Legends & Lattes"
    end

    test "a lone ordering variant is dropped rather than imported alone" do
      candidates = [
        provider_candidate(%{"series" => [%{"name" => "Discworld (Publication Order)"}]})
      ]

      draft = Seed.build(item(%{matches: matches(candidates), tags: %{}}))

      assert draft.work.series == []
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
