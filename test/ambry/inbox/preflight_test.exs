defmodule Ambry.Inbox.PreflightTest do
  @moduledoc """
  The check at the door: what this import would create that the library has.

  A draft is a snapshot of a library that keeps moving, so these tests are
  mostly about the gap between the two — a name settled when nothing of that
  name existed, asked again when something does.
  """
  use Ambry.DataCase

  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.Preflight

  describe "check/1 on a book" do
    test "an empty library collides with nothing" do
      assert Preflight.check(draft(work: creating("Leviathan Wakes", ["James S.A. Corey"]))) == []
    end

    test "a book of the same title and author is found" do
      book = book_titled("Leviathan Wakes", "James S.A. Corey")

      assert [finding] = book_findings(creating("Leviathan Wakes", ["James S.A. Corey"]))
      assert finding.kind == :book
      assert finding.section == :work
      assert finding.label == "Book: Leviathan Wakes"
      assert finding.certain?
      assert [%{label: label, route: {:book, id}}] = finding.matches
      assert id == book.id
      assert label == "Leviathan Wakes by James S.A. Corey"
    end

    # The spellings the providers actually disagree about. None of these is a
    # different book, and every one of them used to be a second Book row.
    test "punctuation, capitalisation, articles and accents do not make a different book" do
      book_titled("The Princess Bride", "William Goldman")

      for title <- ["princess bride", "Princess Bride", "The  Princess: Bride"] do
        assert [_found] = book_findings(creating(title, ["William Goldman"])),
               "expected #{title} to find The Princess Bride"
      end
    end

    test "an accented title finds its unaccented twin" do
      book_titled("Les Misérables", "Victor Hugo")

      assert [_found] = book_findings(creating("Les Miserables", ["Victor Hugo"]))
    end

    test "the author is spelled the way the other provider spells it" do
      book_titled("Leviathan Wakes", "James S. A. Corey")

      assert [finding] = book_findings(creating("Leviathan Wakes", ["James S.A. Corey"]))
      assert finding.certain?
    end

    # Two books really can share a title, so this is shown and marked rather
    # than hidden: the operator is the one who knows which it is.
    test "a title twin by somebody else is offered, but not as a certainty" do
      book_titled("Persuasion", "Jane Austen")

      assert [finding] = book_findings(creating("Persuasion", ["Someone Else"]))
      refute finding.certain?
    end

    test "the certain match is listed first" do
      _other = book_titled("Persuasion", "Someone Else")
      mine = book_titled("Persuasion", "Jane Austen")

      assert [finding] = book_findings(creating("Persuasion", ["Jane Austen"]))
      assert [%{route: {:book, first}}, %{route: {:book, _second}}] = finding.matches
      assert first == mine.id
    end

    test "a different book is not a collision" do
      book_titled("Dune Messiah", "Frank Herbert")

      assert book_findings(creating("Dune", ["Frank Herbert"])) == []
    end

    # The whole point of linking: the operator already said which book this
    # is, so there is nothing left to warn about.
    test "a work that links an existing book creates no book" do
      book = book_titled("Leviathan Wakes", "James S.A. Corey")

      work = %{creating("Leviathan Wakes", ["James S.A. Corey"]) | mode: :link, book_id: book.id}

      assert book_findings(work) == []
    end

    test "a work with no settled title asks nothing" do
      book_titled("Leviathan Wakes", "James S.A. Corey")

      work = %{creating("Leviathan Wakes", []) | title: %Field{value: nil}}

      assert Preflight.check(draft(work: work)) == []
    end
  end

  describe "check/1 on the credits and the people" do
    test "an identity of the same name is found, with whoever is behind it" do
      person = insert(:person, name: "Sarah J. Maas")
      author = insert(:author, name: "Sarah J. Maas", person: person)

      draft = draft(work: %{creating("Some Book", ["Sarah  J.  Maas"]) | title: %Field{}})

      assert [finding] = Preflight.check(draft)
      assert finding.kind == :author
      assert finding.label == "Author: Sarah  J.  Maas"
      assert [%{label: label, route: {:person, person_id}}] = finding.matches
      assert person_id == person.id
      assert label == "#{author.name} (#{person.name})"
    end

    test "a narrator of the same name is found" do
      insert(:narrator, name: "R.C. Bray", person: insert(:person))

      draft =
        draft(
          work: bare_work(),
          recording: %Recording{narrators: [%Credit{name: "RC Bray", kind: :narrator}]}
        )

      assert [finding] = Preflight.check(draft)
      assert finding.kind == :narrator
      assert finding.section == :recording
    end

    test "a person of the same name is found" do
      person = insert(:person, name: "Patricia Rodríguez")

      draft =
        draft(
          work: bare_work(),
          people: [
            %PersonDecision{key: "patriciarodriguez", name: %Field{value: "Patricia Rodriguez"}}
          ]
        )

      assert [finding] = Preflight.check(draft)
      assert finding.kind == :person
      assert finding.section == :people
      assert [%{route: {:person, id}}] = finding.matches
      assert id == person.id
    end

    # A tombstone is the operator saying "not this one". It creates nothing,
    # so it can collide with nothing.
    test "a removed credit creates nothing" do
      insert(:author, name: "Sarah J. Maas")

      credit = %Credit{name: "Sarah J. Maas", kind: :author, removed: true}
      draft = draft(work: %{bare_work() | authors: [credit]})

      assert Preflight.check(draft) == []
    end

    test "a linked credit creates nothing" do
      author = insert(:author, name: "Sarah J. Maas")

      credit = %Credit{name: "Sarah J. Maas", kind: :author, mode: :link, identity_id: author.id}
      draft = draft(work: %{bare_work() | authors: [credit]})

      assert Preflight.check(draft) == []
    end
  end

  describe "check/1 on the series and the set" do
    test "a series of the same name is found, filler words and all" do
      series = insert(:series, name: "Bill Hodges Trilogy")

      link = %SeriesLink{name: "Bill Hodges"}
      draft = draft(work: %{bare_work() | series: [link]})

      assert [finding] = Preflight.check(draft)
      assert finding.kind == :series
      assert [%{route: {:series, id}}] = finding.matches
      assert id == series.id
    end

    # This one is not a duplicate waiting to happen but an import that fails:
    # `recording_groups (book_id, name)` is unique, so creating it raises a
    # constraint error out of the middle of the transaction.
    test "a set the linked book already has is found" do
      book = book_titled("Leviathan Wakes", "James S.A. Corey")
      group = insert(:recording_group, book: book, name: "Graphic Audio LLC")

      draft =
        draft(
          work: %{bare_work() | mode: :link, book_id: book.id},
          recording: %Recording{recording_group: %GroupLink{name: "Graphic  Audio  LLC"}}
        )

      assert [finding] = Preflight.check(draft)
      assert finding.kind == :set
      assert [%{route: {:set, id}}] = finding.matches
      assert id == group.id
    end

    # A set belongs to a book, so a book that doesn't exist yet has none of
    # them to collide with — whatever else is called that elsewhere.
    test "a set on a book this import would create is not compared to other books' sets" do
      other = book_titled("Something Else", "Someone")
      insert(:recording_group, book: other, name: "Graphic Audio LLC")

      draft =
        draft(
          work: bare_work(),
          recording: %Recording{recording_group: %GroupLink{name: "Graphic Audio LLC"}}
        )

      assert Preflight.check(draft) == []
    end
  end

  describe "check/1 overall" do
    test "nothing is asked about a replacement, which creates nothing" do
      book_titled("Leviathan Wakes", "James S.A. Corey")
      media = insert(:media, book: insert(:book))

      draft =
        draft(
          work: creating("Leviathan Wakes", ["James S.A. Corey"]),
          replacement: %Replacement{mode: :replace, media_id: media.id, approved: true}
        )

      assert Preflight.check(draft) == []
    end

    # One import, several kinds of thing to make, each asked about separately.
    test "every kind of collision is reported together, in a fixed order" do
      book = book_titled("Leviathan Wakes", "James S.A. Corey")
      insert(:series, name: "The Expanse")
      insert(:narrator, name: "Jefferson Mays", person: insert(:person))
      insert(:person, name: "Jefferson Mays")
      insert(:recording_group, book: book, name: "Graphic Audio LLC")

      draft =
        draft(
          work: %{
            creating("Leviathan Wakes", ["James S.A. Corey"])
            | mode: :link,
              book_id: book.id,
              series: [%SeriesLink{name: "The Expanse"}]
          },
          recording: %Recording{
            narrators: [%Credit{name: "Jefferson Mays", kind: :narrator}],
            recording_group: %GroupLink{name: "Graphic Audio LLC"}
          },
          people: [%PersonDecision{key: "jeffersonmays", name: %Field{value: "Jefferson Mays"}}]
        )

      assert [:series, :author, :set, :narrator, :person] =
               draft |> Preflight.check() |> Enum.map(& &1.kind)
    end

    test "a nil draft asks nothing" do
      assert Preflight.check(nil) == []
    end

    # The list is compared for equality when the operator says to go ahead
    # anyway, so it has to be the same list twice.
    test "the same draft against the same library gives the same answer" do
      book_titled("Persuasion", "Jane Austen")
      book_titled("Persuasion", "Someone Else")
      insert(:author, name: "Jane Austen")

      draft = draft(work: creating("Persuasion", ["Jane Austen"]))

      assert Preflight.check(draft) == Preflight.check(draft)
    end
  end

  # The book tests are about books. A draft that means to create an author the
  # library also has is a real collision and gets its own test above; here it
  # is noise.
  defp book_findings(work) do
    work |> then(&draft(work: &1)) |> Preflight.check() |> Enum.filter(&(&1.kind == :book))
  end

  defp draft(fields) do
    struct!(%Draft{work: bare_work(), recording: %Recording{}, people: []}, fields)
  end

  defp bare_work, do: %Work{mode: :create, title: %Field{}, authors: [], series: []}

  defp creating(title, authors) do
    %Work{
      mode: :create,
      title: %Field{value: title},
      authors: Enum.map(authors, &%Credit{name: &1, kind: :author}),
      series: []
    }
  end

  defp book_titled(title, author_name) do
    author = insert(:author, name: author_name)
    insert(:book, title: title, book_authors: [build(:book_author, author: author)])
  end
end
