defmodule Ambry.Inbox.Draft.Seed do
  @moduledoc """
  Builds a draft from what an item's files and providers had to say.

  Seeding is where the auto-approval rules live. Their shared logic: a rule
  may only settle a decision when getting it wrong would be *cheap* — either
  because the answer is identity rather than similarity (an ASIN, an exact
  name match), or because there was only ever one answer on offer. Everything
  else is left for a human, because the inbox exists precisely for the cases
  automation gets wrong.

  ## The rules

    * **work identity** — the question is only ever "is this a book you
      already have". A local title+author match at ≥ 0.95 settles it as *that*
      book; a weaker local hit is offered and never assumed, because attaching
      a recording to the wrong existing book is worse than one duplicate Book
      and much harder to notice. **No local hit at all settles it as a new
      book**, because that is what the local search just answered — how good
      the provider records are is a separate question the fields report.
    * **recording identity** — settled when an ASIN or a confident match says
      which catalogue entry this is, and settled when nothing was found at all
      (plenty of good rips are in no storefront). A *doubted* match settles
      nothing and records why: the wrong recording of the right book is the
      most expensive mistake available here and the hardest to notice later.
    * **scalar** — nothing proposed and optional: waived. One proposal: taken.
      Several that agree once normalized: taken. Several that disagree:
      the operator's. Format labels are not a disagreement — "Neuromancer" and
      "Neuromancer (Unabridged)" are one answer written two ways, and the
      cleaner spelling wins.
    * **credit** — one exact identity match: linked. No match at all, name
      from a provider-matched work: created 1:1. A *Person* matches but the
      identity doesn't: always the operator's, because "is this the same
      human?" is exactly the judgment not to automate.
    * **new credit from tags, never automatically** — tag names come from the
      multi-value splitting 1b calls knowingly imperfect ("Sanderson,
      Brandon"). This is the rule that stops the inbox quietly filling the
      library with malformed people.
    * **series number** — never invented, but every provider we use reports
      one, so it usually arrives with the match. A tag's number belongs to the
      series the tag named; it is borrowed for a provider's series only when
      the file named none and there is exactly one proposal.

  ## Re-seeding

  The candidate list is a question with one right answer — the file is a
  recording of exactly one work — so choosing a different candidate refills
  the fields from it (`reseed_work/4`, `reseed_recording/4`). Anything the
  operator typed survives, because 1d's whole point is that curation outranks
  any source.
  """

  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library
  alias Ambry.Library.Location
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  # How closely an existing Book has to match before the import proposes
  # linking to it rather than creating one. Deliberately high: attaching a
  # recording to the wrong book is a worse outcome than one duplicate Book,
  # and it's much harder to notice.
  @strong_local 0.95

  # How sure a recording match must be before its metadata is allowed to
  # describe this file.
  @trusted_recording 0.75

  # And the same for a work. Lower than the recording's bar on purpose: the
  # cost of being wrong is different. A wrong recording is the wrong reading of
  # the right book and is nearly invisible afterwards; a wrong work is a
  # visibly wrong title sitting on the form, in front of an operator who is
  # already looking at it.
  @trusted_work 0.65

  @doc """
  Builds a fresh draft for an item from its matches, tags and release name.
  """
  def build(%InboxItem{} = item) do
    hints = AutoMatch.hints(item)
    tags = item.tags || %{}
    matches = item.matches || %{}

    work_level = Map.get(matches, "work", %{})
    recording_level = Map.get(matches, "recording", %{})

    work = work(work_level, hints, tags, item)

    %Draft{
      evidence: evidence(item),
      stale: false,
      work: work,
      recording: recording(recording_level, hints, tags, item),
      destination: destination(item)
    }
    |> reseed_people(item)
  end

  @doc """
  Marks a draft as built against evidence that has since changed.

  Discovery must never rewrite a curated choice, so a file that moved or was
  replaced makes the draft *say so* rather than silently re-seeding over the
  operator's work.
  """
  def restale(nil, _item), do: nil

  def restale(%Draft{} = draft, %InboxItem{} = item) do
    %{draft | stale: draft.evidence != evidence(item)}
  end

  # Cheap and sufficient: what a draft was built against is the set of files
  # and their probe. Neither a rename nor a replacement can slip past it.
  defp evidence(%InboxItem{} = item) do
    :erlang.phash2({item.files, item.probe}) |> Integer.to_string()
  end

  ## destination

  # Any input may feed any output, so the root is chosen per import rather
  # than fixed on the location. The single-root case — which is nearly all of
  # them — resolves silently: being asked to pick from a list of one is not a
  # decision, it's an interruption.
  def destination(%InboxItem{} = item) do
    item = Repo.preload(item, :location)

    case item.location do
      %Location{kind: :downloads} = location -> managed_destination(location)
      _adopted_in_place -> %Destination{custody: :external, approved: true}
    end
  end

  defp managed_destination(location) do
    roots = Library.library_roots()

    # A location may still *prefer* a root; it just doesn't bind to one.
    preferred = Enum.find(roots, &(&1.id == location.target_root_id))

    case {preferred, roots} do
      {%Location{} = root, _several} -> settled(root, location)
      {nil, [only]} -> settled(only, location)
      {nil, _none_or_several} -> %Destination{custody: :managed, policy: location.import_policy}
    end
  end

  defp settled(root, location) do
    %Destination{
      custody: :managed,
      root_id: root.id,
      policy: location.import_policy,
      approved: true
    }
  end

  ## work

  # The first decision is not "which of these records", it is **is this a book
  # you already have, or a new one**. Those are different outcomes — linking
  # creates nothing and inherits the book's curation — and mixing them into
  # one ranked list made the form ask one question that was really two.
  defp work(level, hints, tags, item) do
    records = records(level)
    local = Map.get(level, "local", []) || []
    confidence = Map.get(level, "confidence")

    {mode, book_id, approved} = work_identity(local)

    # **Only a work we actually believe in gets to fill anything in**, exactly
    # as the recording level has always done. Ticking the top record whatever
    # its score meant a weak match quietly supplied the title, the publication
    # date and the authors of a book it wasn't about — the operator's only
    # clue being fields that looked settled and were wrong, which is far worse
    # than fields that are visibly empty.
    {doubt, detail, best} = trust_work(records, level)

    %Work{
      mode: mode,
      book_id: book_id,
      approved: approved,
      confidence: confidence,
      doubt: doubt,
      doubt_detail: detail,
      query: Map.get(level, "query"),
      query_fields: Map.get(level, "query_fields") || %{},
      sources: if(best, do: Enum.map(AutoMatch.top_group(records), &SourceRef.of/1), else: [])
    }
    |> put_work_fields(records, hints, tags, item)
  end

  # Linking to a Book is a different answer and answers itself: the book's own
  # fields are inherited, so there is nothing for a doubted record to spoil.
  defp trust_work([], _level), do: {:nothing_found, nil, nil}

  defp trust_work([best | _rest], level) do
    confidence = Map.get(level, "confidence") || 0.0

    cond do
      best["score"] == 1.0 -> {:none, nil, best}
      confidence >= @trusted_work -> {:none, nil, best}
      true -> {:low_confidence, weak_work_detail(best, confidence), nil}
    end
  end

  defp weak_work_detail(best, confidence) do
    "The closest is #{best["title"]}#{written_by(best["authors"])}, and it isn't a close " <>
      "enough match (#{round(confidence * 100)}%) to describe this book."
  end

  defp written_by(authors) do
    case names(authors) do
      nil -> ""
      names -> " by #{Enum.join(names, ", ")}"
    end
  end

  @doc """
  Re-derives a work's fields from whichever records are currently ticked.

  Ticking a record is what makes it speak: every scalar draws its candidates
  from the ticked set plus the file's tags, which is how the description can
  come from one database and the cover from another. Anything the operator
  typed survives — 1d's whole point is that curation outranks any source.
  """
  def reseed_work(%Work{} = work, %InboxItem{} = item) do
    work
    |> follow_query(item, "work")
    |> put_work_fields(records(item, "work"), AutoMatch.hints(item), item.tags || %{}, item)
  end

  # What was asked of the providers is evidence, not a decision — nobody
  # curates a query string. A curated draft survives a re-match via resettle
  # rather than a rebuild, and its evidence header kept reporting the search
  # from its first seeding while the records below it came from a newer one.
  defp follow_query(struct, %InboxItem{matches: matches}, level) when is_map(matches) do
    case Map.get(matches, level) do
      %{"query" => query} = held ->
        %{struct | query: query, query_fields: Map.get(held, "query_fields") || %{}}

      _unmatched ->
        struct
    end
  end

  defp follow_query(struct, _item, _level), do: struct

  defp put_work_fields(%Work{} = work, records, hints, tags, _item) do
    sources = used(records, work.sources)
    book_id = if work.mode == :link, do: work.book_id

    published = keep_manual(work.published, published_field(sources, tags))

    %{
      work
      | title: keep_manual(work.title, title_field(sources, hints, tags)),
        published: published,
        published_format:
          keep_manual(work.published_format, published_format_field(sources, tags, published)),
        authors: keep_curated(work.authors, author_credits(sources, tags)),
        series: keep_curated(work.series, series_links(sources, tags, book_id))
    }
  end

  @doc """
  The provider records stored for a level.
  """
  def records(%InboxItem{matches: matches}, level) when is_map(matches),
    do: matches |> Map.get(level, %{}) |> records()

  def records(%InboxItem{}, _level), do: []
  def records(level) when is_map(level), do: Map.get(level, "candidates", []) || []
  def records(_level), do: []

  @doc """
  The existing Books that might be this work.
  """
  def local_records(%InboxItem{matches: matches}, level) when is_map(matches),
    do: matches |> Map.get(level, %{}) |> Map.get("local", []) |> List.wrap()

  def local_records(%InboxItem{}, _level), do: []

  # The ticked records, in the order they're listed rather than the order they
  # were ticked, so the chip order in the form is stable.
  defp used(records, refs) do
    Enum.filter(records, fn record -> Enum.any?(refs, &SourceRef.points_at?(&1, record)) end)
  end

  defp from_records(records, key), do: Enum.map(records, &candidate(&1, key))

  # A credit or series the operator has touched survives re-derivation
  # untouched. A field value is cheap to recompute; a credit is not — it may
  # carry a linked identity, a renamed pen name, or two people behind it, and
  # rebuilding it from proposals threw all of that away the moment another
  # record was ticked.
  #
  # Fresh proposals that nothing curated already covers are appended, so
  # ticking a record still brings its people in.
  defp keep_curated(existing, fresh) do
    curated = Enum.filter(existing, & &1.curated)
    taken = MapSet.new(curated, &down(&1.name || ""))

    curated ++ Enum.reject(fresh, &MapSet.member?(taken, down(&1.name || "")))
  end

  # A field the operator typed is theirs; re-seeding from another candidate
  # must not quietly undo a correction. Everything else is provider data being
  # replaced by other provider data, which is exactly what was asked for.
  defp keep_manual(%Field{source: "manual"} = existing, _fresh), do: existing

  # A chip the operator picked stays picked while its proposal is still on
  # offer — re-deriving because some other record was ticked must not quietly
  # move a value they chose. Gated on `curated`, NOT on `chosen_key`: the
  # seeder sets a chosen_key too, so keying on it froze every auto-settled
  # field against all later evidence.
  defp keep_manual(%Field{curated: true} = existing, fresh) when is_binary(existing.chosen_key) do
    # **By key first, then by value.** A key can legitimately disappear while
    # the answer stays on offer: the operator picks the release-name chip,
    # then ticks a record whose title turns out to be identical, and the
    # advisory chip is dropped as a duplicate of it. Looking only for the key
    # then found nothing and silently threw the choice away — measured on the
    # Chambers book, which went from ready to "pick a title" in the middle of
    # a batch import, with no one having touched it.
    chosen =
      Enum.find(fresh.candidates, &(&1.key == existing.chosen_key)) ||
        Enum.find(fresh.candidates, &(&1.value == existing.value))

    case chosen do
      nil ->
        fresh

      chosen ->
        # `curated` has to be carried too, or a choice survives exactly one
        # re-derivation and is movable by the next.
        %{
          fresh
          | value: chosen.value,
            source: chosen.source,
            chosen_key: chosen.key,
            approved: true,
            curated: true
        }
    end
  end

  defp keep_manual(_existing, fresh), do: fresh

  # Reusing a Book already in the library is the best outcome there is — it's
  # what stops a second recording of a work splitting the library — so a
  # convincing local hit is proposed as a link. Anything else is a new book,
  # which is also what an item with no matches at all is: "create a new book"
  # was never a separate answer, just the absence of an existing one.
  defp work_identity(local) do
    case Enum.max_by(local, &(&1["score"] || 0.0), fn -> nil end) do
      %{"id" => id, "score" => score} when score >= @strong_local ->
        {:link, id, true}

      %{} ->
        # A local book close enough to show but not to assume: the operator
        # has to say, because attaching a recording to the wrong existing book
        # is worse than creating one book too many.
        {:create, nil, false}

      # **Nothing in the library could be this book, so it isn't a question.**
      # This used to need a nod whenever the *provider* match was weak, which
      # conflated two unrelated things: how good the records are is what the
      # field decisions report, and it says nothing about whether the library
      # already has the work — that's what the local search just answered, and
      # it answered no.
      #
      # Worse, the control lives inside the "Is this a book you already have?"
      # block, which only renders when there ARE local candidates. So an
      # ordinary import with no local hit showed an outstanding decision, a
      # disabled import button, and **nothing on the page to settle it with**.
      # Same lesson as the photo affordance inside the pen-name fold: a
      # decision the form asks for has to have a control the operator can
      # reach from where they're standing.
      nil ->
        {:create, nil, true}
    end
  end

  # The release name is a fallback, not a peer. Measured across the real
  # library, 96% of releases carry a title in tags and the parser is what the
  # other ~2% rely on — so letting the folder name argue with a provider would
  # make nearly every import ambiguous on its title for no gain.
  # **The file's name is a third opinion about the title, and it was never on
  # offer.** It used to be a `fallback` — visible only when nothing else
  # proposed anything — and it was handed `hints.title`, which *is* the tag
  # title whenever the tags carry one. So the chip could only ever repeat the
  # tags while claiming to come from the release name, and the name's own
  # answer was unreachable on a form that had one.
  #
  # Measured across the operator's real library (198 releases probed): the tag
  # title and the release name disagree on **105** of them, and for a
  # meaningful minority the name is the one telling the truth — the Wayfarers
  # books are tagged `Wayfarers, Book 1` and named
  # `The Long Way to a Small, Angry Planet`.
  #
  # It is offered rather than *preferred*, deliberately. The same measurement
  # kills every rule that would rank one above the other: the name is better
  # for the Wayfarers books and catastrophically worse elsewhere — The Wild
  # Robot's release name yields "Peter Brown", and
  # "Out of Spite, Out of Mind: Magic 2.0, Book 5" truncates to "Out of Spite".
  # Which is right is a judgement, and a judgement belongs on a chip.
  defp title_field(sources, hints, tags) do
    (from_records(sources, "title") ++ [tag_candidate(tags, "book_title")])
    |> scalar(
      required: true,
      equivalence: &same_title?/2,
      prefer: &shorter/2,
      advisory: release_candidate(hints.release_title)
    )
  end

  # **A title and that same title carrying a subtitle are one answer written
  # two ways.** The dominant real-world tag shape is `Title: Series, Book N` —
  # measured across the operator's library, most of the tag titles that look
  # like shelf labels are exactly that — while the catalogues answer with the
  # bare title. Scored as rivals they put "pick a title" on a large share of
  # imports, every time for the same mechanical reason: three of the seven
  # books in one real batch (Battle Ground, A Psalm for the Wild-Built,
  # A Prayer for the Crown-Shy) asked the identical question.
  #
  # This is **asymmetric containment, not a shared prefix**, which is the
  # whole subtlety. Comparing the part before the colon on both sides would
  # merge "The Expanse: Leviathan Wakes" with "The Expanse: Caliban's War" —
  # two different books. One title has to be the *whole* of the other's head:
  #
  #     "Battle Ground: The Dresden Files, Book 17" ≡ "Battle Ground"
  #     "The Expanse: Leviathan Wakes"              ≢ "The Expanse: Caliban's War"
  #     "Dune"                                     ≢ "Dune Messiah"
  #
  # The last one matters: a subtitle is separated by punctuation, so plain
  # word-prefix containment is never enough. `prefer: &shorter/2` then keeps
  # the bare title, which is what the catalogues and the library want.
  defp same_title?(one, other) do
    a = title_key(one)
    b = title_key(other)

    a == b or title_head(one) == b or title_head(other) == a
  end

  # Everything before the first subtitle separator — a colon, or a dash with
  # space around it. A hyphen inside a word ("Wild-Built") is not a separator.
  defp title_head(value) when is_binary(value) do
    value
    |> String.split(~r/\s*:\s|\s+[-–—]\s+/u, parts: 2)
    |> hd()
    |> title_key()
  end

  defp title_head(other), do: title_key(other)

  # "Neuromancer" and "Neuromancer (Unabridged)" are one answer written two
  # ways, and treating that as a disagreement made the operator arbitrate a
  # non-question on a large share of imports — Audible titles carry the format
  # label and work-level providers don't. Only *format* labels are set aside,
  # and only for deciding whether two proposals mean the same thing: both
  # strings stay in the candidate list, and the shorter one wins the field.
  #
  # Deliberately not stripped: "Dramatized Adaptation", "(1 of 3)" and the
  # like. Those name a genuinely different recording, and collapsing them
  # would hide the very distinction the recording level exists to make.
  @format_labels ~r/\b(?:un)?abridged(?:\s+edition)?\b|\baudio\s?book\b|\baudio\s+edition\b/iu

  defp title_key(value) when is_binary(value) do
    value
    |> String.replace(@format_labels, " ")
    # a bracket that held nothing but a format label is now empty
    |> String.replace(~r/[(\[{]\s*[)\]}]/u, " ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> normalize()
  end

  defp title_key(other), do: normalize(other)

  # **Year-only knowledge arrives as a literal January 1st.** Every source
  # does it — the ROADMAP records it for Goodreads-shaped data, and the
  # operator's own files carry it too, which is why the tag date and the
  # provider date were being reported as rival opinions on a large share of
  # imports. "2017-01-01" and "2017-10-03" are not two answers; they are one
  # fact at two precisions, and the precise one is the answer.
  #
  # Two *precise* dates in one year genuinely do disagree, and so do two
  # different years. Both stay the operator's.
  defp same_date?(one, other) do
    case {parse_date(one), parse_date(other)} do
      {%Date{} = a, %Date{} = b} ->
        a == b or (a.year == b.year and (year_only?(a) or year_only?(b)))

      _unparseable ->
        normalize(one) == normalize(other)
    end
  end

  defp more_precise(held, incoming) do
    case {parse_date(held), parse_date(incoming)} do
      {%Date{} = a, %Date{} = b} ->
        if year_only?(a) and not year_only?(b), do: incoming, else: held

      _unparseable ->
        held
    end
  end

  defp year_only?(%Date{month: 1, day: 1}), do: true
  defp year_only?(%Date{}), do: false

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_other), do: nil

  defp published_field(sources, tags) do
    (from_records(sources, "published") ++ [tag_candidate(tags, "published")])
    |> scalar(required: true, equivalence: &same_date?/2, prefer: &more_precise/2)
  end

  # Not derivable from the date *upwards*: year-only knowledge arrives as a
  # literal Jan 1st, and rendering that as a real release day is the exact bug
  # the v1.9.0 punch list fixed for the import forms. Derivable downwards,
  # though — see `Field.follow_date/2`, which is what stops the format sitting
  # unanswered beside a date that has plainly already answered it.
  defp published_format_field(sources, tags, published) do
    (from_records(sources, "published_format") ++ [tag_candidate(tags, "published_format")])
    |> scalar(required: false)
    |> Field.follow_date(published)
    |> default_to("full")
  end

  # Same rule as the work's, on the recording's own records: the format says
  # how much of the release date is real, and follows whichever record won it.
  defp recording_format_field(records, published) do
    records
    |> from_records("published_format")
    |> scalar(required: false)
    |> Field.follow_date(published)
    |> default_to("full")
  end

  defp default_to(%Field{value: nil, candidates: []} = field, value) do
    %{field | value: value, source: "default", approved: true}
  end

  defp default_to(field, _value), do: field

  ## recording

  defp recording(level, hints, tags, item) do
    records = records(level)

    # **Only a recording we actually believe in gets to fill anything in.**
    # Audible's search widens when a narrow query finds nothing, so a book
    # whose only catalogued edition has a different reader still returns that
    # edition — and taking its publisher, release date and cover would quietly
    # describe this file as a recording it is not. A doubted record stays in
    # the list to be ticked; it just isn't ticked for you.
    {doubt, detail, best} = trust(records, level, hints)

    %Recording{
      confidence: Map.get(level, "confidence"),
      query: Map.get(level, "query"),
      query_fields: Map.get(level, "query_fields") || %{},
      doubt: doubt,
      doubt_detail: detail,
      sources: if(best, do: Enum.map(AutoMatch.top_group(records), &SourceRef.of/1), else: []),
      # Settled when we actually know which recording this is — a trusted
      # match — or when there was nothing to choose between. A doubted record
      # leaves the question open rather than being adopted quietly; that
      # ambiguity used to be invisible, showing up only as fields that
      # mysteriously stayed empty.
      approved: doubt in [:none, :nothing_found]
    }
    |> put_recording_fields(records, tags, item)
  end

  @doc """
  Re-derives a recording's fields from whichever records are currently ticked.
  """
  def reseed_recording(%Recording{} = recording, %InboxItem{} = item) do
    recording
    |> follow_query(item, "recording")
    |> put_recording_fields(records(item, "recording"), item.tags || %{}, item)
  end

  # **Only records of this recording describe this recording.** Work-level
  # records used to feed description, publisher and cover, and all three were
  # wrong:
  #
  #   * `publisher` means who is responsible for the *audiobook* — Audible
  #     Studios, Macmillan Audio, Graphic Audio, Soundbooth Theater. A work
  #     record's publisher is whoever printed the book, which is a different
  #     company answering a different question.
  #   * `description` from an audio edition carries what the print blurb
  #     doesn't: the performance, the narrator, awards it won for the reading.
  #   * `cover` from a work record is a portrait print jacket, and audiobook
  #     art is square.
  #
  # A database's audio *editions* answer all three properly, and those arrive
  # as recording records.
  defp put_recording_fields(%Recording{} = recording, records, tags, item) do
    mine = used(records, recording.sources)
    published = keep_manual(recording.published, scalar(from_records(mine, "published")))

    %{
      recording
      | title: keep_manual(recording.title, scalar([], required: false)),
        published: published,
        published_format:
          keep_manual(
            recording.published_format,
            recording_format_field(mine, published)
          ),
        publisher:
          keep_manual(
            recording.publisher,
            scalar(from_records(mine, "publisher") ++ [tag_candidate(tags, "publisher")])
          ),
        # Two databases will never write the same description, and two cover
        # URLs are two pictures nothing here can compare without fetching and
        # looking at them. Reporting either as "sources disagree" asks the
        # operator to arbitrate a non-question on every single import — these
        # are alternatives, so one is taken and the rest stay one click away.
        description:
          keep_manual(
            recording.description,
            scalar(from_records(mine, "description") ++ [tag_candidate(tags, "description")],
              alternatives: true
            )
          ),
        cover: keep_manual(recording.cover, cover_field(mine, tags, item)),
        narrators: keep_curated(recording.narrators, narrator_credits(mine, tags))
    }
  end

  # An ASIN hit is identity, so it needs no corroboration. Otherwise the
  # narrator decides: when the file names a reader and the candidate names a
  # different one, this is the wrong recording of the right book — the single
  # most common way recording-level matching goes wrong, and the one the
  # operator is least likely to notice after the fact.
  #
  # Returns why it isn't trusted as well as whether, because "no provider
  # listed this" and "a provider listed a different reader's edition" call for
  # completely different things from the operator, and an empty form says
  # neither.
  defp trust([], _level, _hints), do: {:nothing_found, nil, nil}

  defp trust([best | _rest], level, hints) do
    confidence = Map.get(level, "confidence") || 0.0

    cond do
      best["score"] == 1.0 ->
        {:none, nil, best}

      conflict = narrator_conflict(best, hints) ->
        {:narrator_conflict, conflict, nil}

      confidence >= @trusted_recording ->
        {:none, nil, best}

      true ->
        {:low_confidence, low_confidence_detail(best, confidence), nil}
    end
  end

  defp low_confidence_detail(best, confidence) do
    "The closest is #{best["title"]}#{narrated_by(best["narrators"])}, and it isn't a close " <>
      "enough match (#{round(confidence * 100)}%) to describe this file."
  end

  defp narrated_by(narrators) do
    case names(narrators) do
      nil -> ""
      names -> " read by #{Enum.join(names, ", ")}"
    end
  end

  defp narrator_conflict(_best, %{narrator: nil}), do: nil

  defp narrator_conflict(best, %{narrator: narrator}) do
    case names(best["narrators"]) do
      nil ->
        nil

      names ->
        if Enum.all?(names, &(String.jaro_distance(down(&1), down(narrator)) < 0.85)) do
          "The file says #{narrator} reads this; the closest catalogue entry " <>
            "(#{best["title"]}) is read by #{Enum.join(names, ", ")}. Those are " <>
            "different recordings of the same book."
        end
    end
  end

  defp down(string), do: String.downcase(String.trim(string))

  # Embedded art and a provider cover are both real answers, so two of them is
  # a choice rather than a winner. The embedded candidate carries the audio
  # file to extract from; approval does the extracting.
  defp cover_field(sources, tags, item) do
    embedded =
      if tags["has_cover_art"] && item.files != [] do
        %Candidate{
          value: List.first(item.files),
          source: "embedded",
          label: "Embedded in the file",
          key: "embedded"
        }
      end

    (from_records(sources, "cover_url") ++ [embedded])
    |> scalar(required: false, alternatives: true)
  end

  ## credits

  defp author_credits(records, tags) do
    records
    |> proposed_names("authors")
    |> or_from_tags(tags, "authors")
    |> Enum.map(fn {name, source} -> credit(name, :author, source) end)
  end

  # A cast label is not a person to create. When a record is ticked its real
  # cast supplies the credits anyway; this is for the case where nothing is,
  # and "Full Cast" would otherwise be proposed as a human to add to the
  # library.
  defp narrator_credits(records, tags) do
    records
    |> proposed_names("narrators")
    |> or_from_tags(tags, "narrators")
    |> Enum.reject(fn {name, _source} -> AutoMatch.placeholder_narrator?(name) end)
    |> Enum.map(fn {name, source} -> credit(name, :narrator, source) end)
  end

  ## people

  @doc """
  Re-points a draft's references at rows that exist now.

  For when the library moved under a queued item — another item that shared a
  person, an identity or a series was approved in between. **Deliberately not
  a re-seed.** Re-deriving the whole draft also re-opens questions the
  operator already answered: measured on a real batch, the Chambers item was
  ready, a *different* import committed, and its tag-derived narrator credit
  silently went back to unapproved because a fresh credit from tags is never
  auto-approved. Nobody had touched it.

  So this changes exactly one thing and only in one direction: a credit,
  series, or the work identity itself that meant to **create** something,
  and now finds exactly one thing of that name already there, becomes a
  **link** to it. Approval state, values, chips and curation are all left as
  they were — the question stays answered, the answer just resolves to a row
  that exists.

  Anything the operator curated is skipped outright, and an *ambiguous* result
  (two identities of one name) is left alone too: that is a real question, and
  inventing an answer to it is the judgement this whole form exists not to
  make.
  """
  def relink(%Draft{} = draft, %InboxItem{} = item) do
    draft
    |> relink_work(item)
    |> update_in([Access.key(:work), Access.key(:authors)], &relink_credits(&1, :author))
    |> update_in([Access.key(:recording), Access.key(:narrators)], &relink_credits(&1, :narrator))
    |> update_in(
      [Access.key(:work), Access.key(:series)],
      &Enum.map(&1 || [], fn s -> relink_series(s) end)
    )
    |> reconcile_people(item)
    |> reopen_new_person_questions()
  end

  # The one case where relink *reopens* a question rather than resolving one.
  # A credit auto-approves on the premise "nobody by that name at all" — and
  # a sibling import can invalidate it: Joyland created the person Stephen
  # King, and Holly's NARRATOR credit for him (an identity Joyland didn't
  # make) then sailed through approval and created a second Stephen King.
  # The seeder never automates "is this the same human?", so the sibling
  # import may not either: the credit goes back to unapproved, exactly the
  # shape the seeder would have produced had the person existed at seed
  # time. Curated credits and people are the operator's and stay put — so
  # answering the reopened question is final.
  defp reopen_new_person_questions(%Draft{} = draft) do
    people = Map.new(draft.people, &{&1.key, &1})

    draft
    |> update_in(
      [Access.key(:work), Access.key(:authors)],
      &Enum.map(&1, fn credit -> reopen_personhood(credit, people) end)
    )
    |> update_in(
      [Access.key(:recording), Access.key(:narrators)],
      &Enum.map(&1, fn credit -> reopen_personhood(credit, people) end)
    )
  end

  defp reopen_personhood(%Credit{mode: :create, curated: false, approved: true} = credit, people) do
    reopen? =
      Enum.any?(credit.person_keys, fn key ->
        case people[key] do
          %PersonDecision{mode: :create, curated: false} = person ->
            name = Field.value(person.name)
            is_binary(name) and person_matches(name) != []

          _linked_curated_or_missing ->
            false
        end
      end)

    if reopen?, do: %{credit | approved: false}, else: credit
  end

  defp reopen_personhood(credit, _people), do: credit

  # Two queued recordings of one work: importing the first creates the Book
  # and the second still says "create" — the split library the module doc
  # above names as the same bug waiting for Books, now closed the same way.
  # A work the seeder settled as new, whose title now matches exactly one
  # Book with an overlapping author, becomes a link to it; the fields are
  # then re-derived for link mode (series already on the book stop being
  # proposed), with `keep_manual`/`keep_curated` holding every answered
  # question. An identity the operator chose is curated and never touched,
  # and anything short of exactly-one-with-matching-author is left alone —
  # linking a recording to the wrong existing book is the worst outcome this
  # form can produce.
  defp relink_work(%Draft{work: %Work{mode: :create, curated: false} = work} = draft, item) do
    with title when is_binary(title) <- Field.value(work.title),
         [book] <- books_titled(title),
         true <- authors_overlap?(book, work) do
      linked = %{work | mode: :link, book_id: book.id, approved: true}
      %{draft | work: reseed_work(linked, item)}
    else
      _no_single_certain_match -> draft
    end
  end

  defp relink_work(draft, _item), do: draft

  # Fetched by keyword and filtered on `title_key/1` — exact identity, but
  # case, punctuation and leading articles don't make a different book: the
  # operator's two Princess Bride releases are titled "Princess Bride" and
  # "The Princess Bride", and a lower(=) comparison left the twin unlinked
  # over the article.
  defp books_titled(title) do
    key = AutoMatch.title_key(title)

    title
    |> Books.match_keywords()
    |> Books.match_books(25)
    |> Enum.filter(&(AutoMatch.title_key(&1.title) == key))
  end

  defp authors_overlap?(book, %Work{authors: credits}) do
    credited =
      for %Credit{name: name} <- credits || [],
          is_binary(name),
          into: MapSet.new(),
          do: AutoMatch.person_key(name)

    held = MapSet.new(book.authors, &AutoMatch.person_key(&1.name))

    # A draft with no author credits at all has nothing to disagree with —
    # but then the title alone is not identity enough to link on.
    not MapSet.disjoint?(credited, held)
  end

  # Membership only: a decision whose key is still referenced is left exactly
  # as it is. `reseed_people/2` would *rebuild* the uncurated ones, which is
  # right after a record tick (new records mean new candidates) and wrong
  # here — it re-opened a person the operator had already settled, and the
  # Chambers item went from ready to "Person: Patricia Rodriguez" in the
  # middle of a batch with nobody having touched it.
  defp reconcile_people(%Draft{} = draft, %InboxItem{} = item) do
    matched = people_matches(item)
    existing = Map.new(draft.people, &{&1.key, &1})
    named = credited_names(draft)

    people =
      draft
      |> Draft.referenced_keys()
      |> Enum.map(fn key ->
        Map.get(existing, key) || person_decision(key, named[key], matched_for(matched, key))
      end)

    %{draft | people: people}
  end

  defp relink_credits(credits, kind), do: Enum.map(credits || [], &relink_credit(&1, kind))

  defp relink_credit(%Credit{curated: true} = credit, _kind), do: credit

  defp relink_credit(%Credit{mode: :create, name: name} = credit, kind) when is_binary(name) do
    case identity_matches(name, kind) do
      # Exactly one identity of this name now exists — the same rule the
      # seeder applies, running against facts it didn't have. The person
      # reference goes with it: a linked identity already has its human, so
      # `reseed_people/2` drops the decision that would have made a second.
      [%{exact: true} = match] ->
        %{
          credit
          | mode: :link,
            identity_id: match.identity_id,
            candidates: [match],
            person_keys: []
        }

      _none_or_several ->
        credit
    end
  end

  defp relink_credit(credit, _kind), do: credit

  defp relink_series(%SeriesLink{curated: true} = link), do: link

  defp relink_series(%SeriesLink{mode: :create, name: name} = link) when is_binary(name) do
    case Repo.all(where(Series, [s], fragment("lower(?)", s.name) == ^String.downcase(name))) do
      [one] ->
        %{
          link
          | mode: :link,
            series_id: one.id,
            candidates: [%SeriesLink.Match{series_id: one.id, name: one.name, exact: true}]
        }

      _none_or_several ->
        link
    end
  end

  defp relink_series(link), do: link

  @doc """
  Brings the draft's people into line with whoever the credits now reference.

  Runs after every change that can move a credit, which is why it is one
  function rather than seed-time and edit-time copies: a person nobody credits
  any more has no reason to sit on the form, and a credit naming somebody new
  needs a decision minted for them.

  **A curated person keeps their decisions, not their evidence.** Skipping
  them wholesale meant "look again" wrote fresh candidates into `matches` and
  the form showed nothing new — for exactly the people the button exists for,
  since renaming a person is what marks them curated. So their candidate lists
  are rebuilt like everyone else's, while `keep_manual/2` pins whatever the
  operator settled — the same field-level rule the work and the recording
  already follow.
  """
  def reseed_people(%Draft{} = draft, %InboxItem{} = item) do
    matched = people_matches(item)
    existing = Map.new(draft.people, &{&1.key, &1})
    named = credited_names(draft)

    people =
      draft
      |> Draft.referenced_keys()
      |> Enum.map(fn key ->
        case Map.get(existing, key) do
          %PersonDecision{curated: true} = curated ->
            refreshed_person(curated, named[key], matched_for(matched, key))

          untouched_or_new ->
            keep_person_fields(
              untouched_or_new,
              person_decision(key, named[key], matched_for(matched, key))
            )
        end
      end)

    %{draft | people: people}
  end

  # An untouched person is rebuilt wholesale, but a field the operator settled
  # inside one survives the rebuild: picking a photo curates the *field*, not
  # the person, and re-derivation moving a picked photo is the same broken
  # rule whichever level it happens at.
  defp keep_person_fields(nil, fresh), do: fresh

  defp keep_person_fields(%PersonDecision{} = was, fresh) do
    %{
      fresh
      | name: keep_manual(was.name, fresh.name),
        image: keep_manual(was.image, fresh.image),
        description: keep_manual(was.description, fresh.description)
    }
  end

  # Evidence is matched against what the person is called *now*, not what the
  # credit says: the credit holds the pen name, and the human behind it being
  # renamed is precisely when somebody searches again. Mode, link, approval
  # and every settled field stay the operator's.
  defp refreshed_person(%PersonDecision{} = person, named, matched) do
    {credited, source} = named || {person.key, nil}
    name = Field.value(person.name) || credited
    candidates = named_candidates(matched, name)
    {doubt, detail} = person_doubt(matched, candidates, name)

    %{
      person
      | doubt: doubt,
        doubt_detail: detail,
        sources: Enum.map(candidates, &SourceRef.of/1),
        name: keep_manual(person.name, person_name_field(credited, source, candidates)),
        image: keep_manual(person.image, person_image_field(candidates)),
        description: keep_manual(person.description, person_description_field(candidates))
    }
  end

  # What each credited human is called and who said so, taken from the credit
  # that references them. The credit is the only thing that knows: a key is a
  # normalised string and a provider record may spell the name differently.
  defp credited_names(%Draft{} = draft) do
    for credit <- credits_of(draft),
        credit.mode == :create,
        key <- credit.person_keys,
        into: %{},
        do: {key, {credit.name, credit.source}}
  end

  defp credits_of(%Draft{} = draft) do
    ((draft.work && draft.work.authors) || []) ++
      ((draft.recording && draft.recording.narrators) || [])
  end

  # One human, asked the same three questions as a work or a recording:
  # which one is this (identity), which records describe them (evidence), and
  # which record each field takes its value from (preference).
  defp person_decision(key, named, matched) do
    {name, source} = named || {key, nil}
    candidates = named_candidates(matched, name)

    {doubt, detail} = person_doubt(matched, candidates, name)

    %PersonDecision{
      key: key,
      mode: :create,
      doubt: doubt,
      doubt_detail: detail,
      sources: Enum.map(candidates, &SourceRef.of/1),
      name: person_name_field(name, source, candidates),
      image: person_image_field(candidates),
      description: person_description_field(candidates),
      # Same bar the credit clears: a provider-matched name is settled, a
      # tag-derived one is a proposal. A person we found nobody for has
      # nothing left to decide beyond the name, so it doesn't add a question;
      # one we found the *wrong* people for does.
      approved: provider?(source) and doubt != :low_confidence
    }
  end

  # Only records that are actually about this human may propose anything.
  # Person search is recall-first — anything sharing a name token is offered —
  # which is right for a grid the operator reads and wrong for a field's
  # candidate list. See `AutoMatch.person_proposal/1` for what that recall
  # looks like on the operator's real library.
  defp named_candidates(nil, _name), do: []

  defp named_candidates(matched, name) do
    matched
    |> Map.get("candidates", [])
    |> Enum.filter(&same_human?(&1["name"], name))
  end

  defp same_human?(one, other) when is_binary(one) and is_binary(other),
    do: AutoMatch.person_key(one) == AutoMatch.person_key(other)

  defp same_human?(_one, _other), do: false

  # What the operator reads beside the credited spelling. The credit carries a
  # provider *id*, not a sentence.
  defp credited_label("provider:" <> id), do: id
  defp credited_label("tags"), do: "The file's tags"
  defp credited_label(_other), do: "The file's tags"

  defp person_doubt(nil, _candidates, _name), do: {:nothing_found, nil}

  defp person_doubt(matched, candidates, name) do
    offered = Map.get(matched, "candidates", [])

    cond do
      candidates != [] ->
        {:none, nil}

      offered == [] ->
        {:nothing_found, nil}

      # Found people, none of them this one. Worth saying out loud rather than
      # reporting "nothing found": the difference is whether looking again is
      # likely to help.
      true ->
        {:low_confidence,
         "No database has anybody called #{name}. The closest were " <>
           (offered |> Enum.map(& &1["name"]) |> Enum.uniq() |> Enum.take(3) |> Enum.join(", ")) <>
           "."}
    end
  end

  defp person_name_field(name, source, candidates) do
    # The credited spelling leads, because that is what the book itself says.
    # A provider spelling it differently is an alternative, not a correction.
    [
      %Candidate{
        value: name,
        source: source || "tags",
        label: credited_label(source),
        key: "credit"
      }
    ]
    |> Enum.concat(
      Enum.map(candidates, fn candidate ->
        %Candidate{
          value: candidate["name"],
          source: candidate["source"],
          label: candidate["provider_name"],
          key: Candidate.key_for(candidate)
        }
      end)
    )
    |> scalar(required: true, alternatives: true)
  end

  # Every photo every database has of them, because the job is not "find a
  # photo" but "find one that survives a circular crop" — the obvious portrait
  # is frequently the one that doesn't. One candidate per image, so the
  # alternatives are reachable in one click.
  defp person_image_field(candidates) do
    for candidate <- candidates,
        {url, index} <- Enum.with_index(List.wrap(candidate["images"])),
        is_binary(url) and url != "" do
      %Candidate{
        value: url,
        source: candidate["source"],
        label: candidate["provider_name"],
        key: "#{Candidate.key_for(candidate)}##{index}"
      }
    end
    |> scalar(alternatives: true)
  end

  # Wikipedia's lead paragraph, TMDB's biography and a book database's blurb
  # are three different texts about one person, so they are alternatives too —
  # never a disagreement to arbitrate.
  defp person_description_field(candidates) do
    for candidate <- candidates, text = usable_bio(candidate["description"]) do
      %Candidate{
        value: text,
        source: candidate["source"],
        label: candidate["provider_name"],
        key: Candidate.key_for(candidate)
      }
    end
    |> scalar(alternatives: true)
  end

  # rreading-glasses returns the literal string "N/A" where it has no
  # biography, and storing that as somebody's life story is worse than leaving
  # it blank — blank is visibly unfinished, "N/A" looks decided.
  @nonsense_bios ["n/a", "na", "none", "unknown", "no description", "-", "."]

  defp usable_bio(text) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed != "" and String.downcase(trimmed) not in @nonsense_bios, do: trimmed
  end

  defp usable_bio(_other), do: nil

  # What matching found out about the humans this item credits, keyed by
  # `AutoMatch.person_key/1`.
  defp people_matches(%InboxItem{matches: matches}) when is_map(matches),
    do: Map.get(matches, "people") || %{}

  defp people_matches(_item), do: %{}

  # By key first, then by key *equivalence*: items matched before the person
  # key became punctuation-insensitive stored their evidence under the older
  # spelling-sensitive keys, and that evidence should not go dark because the
  # sameness rule improved.
  defp matched_for(matched, key) do
    Map.get(matched, key) ||
      Enum.find_value(matched, fn {held, evidence} ->
        if AutoMatch.person_key(held) == AutoMatch.person_key(key), do: evidence
      end)
  end

  # Names across every ticked record, in first-mentioned order and deduped by
  # `person_key/1` — the sameness rule for humans, so "James S.A. Corey" and
  # "James S. A. Corey" from two databases are one credit, not two. Deduping
  # only case-insensitively left both, and approval would have made a
  # duplicate library author out of a spelling difference.
  defp proposed_names(records, key) do
    records
    |> Enum.flat_map(fn record ->
      record |> Map.get(key) |> names() |> List.wrap() |> Enum.map(&{tidy(&1), source_of(record)})
    end)
    |> Enum.uniq_by(fn {name, _source} -> AutoMatch.person_key(name) end)
  end

  # **Doubled spaces in a credited name are not a different human.**
  # rreading-glasses answers "Jim  Butcher" for The Dresden Files, and the name
  # is stored verbatim — so the library gets a person spelled with two spaces,
  # and `identity_matches/2` (an exact `lower(name)` comparison) will not match
  # the next import that spells it with one. That is a duplicate author waiting
  # to happen, and it is invisible: the two render identically in HTML, which
  # collapses whitespace.
  #
  # Tidied at the *proposal* stage, like the unparseable series numbers — the
  # record still says what it said.
  defp tidy(name) when is_binary(name), do: name |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp tidy(other), do: other

  # The file only gets a say when no record proposed anybody. A tag name is a
  # weaker proposal — 1b's multi-value splitting is knowingly imperfect — so it
  # never argues with a record, it just fills a silence.
  defp or_from_tags([], tags, key) do
    tags |> Map.get(key) |> names() |> List.wrap() |> Enum.map(&{tidy(&1), "tags"})
  end

  defp or_from_tags(proposed, _tags, _key), do: proposed

  defp credit(name, kind, source) do
    matches = identity_matches(name, kind)
    people = person_matches(name)

    base = %Credit{name: name, kind: kind, source: source, candidates: matches}
    # Who is behind the credit is a reference now, not an embed — the human
    # themselves is decided once, in `draft.people`.
    keys = Credit.new_person_default(name)

    case {matches, people} do
      # exactly one existing identity by that name — link it and move on
      {[%{exact: true} = match], _people} ->
        %{base | mode: :link, identity_id: match.identity_id, approved: true}

      # nobody by that name at all: create it, backed by one new person.
      # Auto only when a provider-matched work supplied the name — tag names
      # are split by a knowingly imperfect rule.
      {[], []} ->
        %{base | mode: :create, person_keys: keys, approved: provider?(source)}

      # a Person exists but this identity doesn't — "is this the same human?"
      # is never automated
      {[], _people} ->
        %{base | mode: :create, person_keys: keys, approved: false}

      # more than one identity shares this name; two people really can
      {_several, _people} ->
        %{base | mode: :create, person_keys: keys, approved: false}
    end
  end

  # The SQL twin of `AutoMatch.person_key/1`, so "James S.A. Corey" in a
  # record finds the library's "James S. A. Corey" and "T.J. Klune" finds
  # "TJ Klune". Still identity, not similarity — a spelling difference in
  # punctuation or spacing is the same name, a different word is not.
  @name_key_sql "regexp_replace(lower(?), '[^[:alnum:]]+', '', 'g')"

  defp identity_matches(name, :author) do
    Author
    |> where([a], fragment(@name_key_sql, a.name) == ^AutoMatch.person_key(name))
    |> preload(:people)
    |> Repo.all()
    |> Enum.map(fn author ->
      %Credit.Match{
        identity_id: author.id,
        name: author.name,
        people: author.people |> Enum.map_join(" and ", & &1.name) |> presence(),
        exact: true
      }
    end)
  end

  defp identity_matches(name, :narrator) do
    Narrator
    |> where([n], fragment(@name_key_sql, n.name) == ^AutoMatch.person_key(name))
    |> preload(:person)
    |> Repo.all()
    |> Enum.map(fn narrator ->
      %Credit.Match{
        identity_id: narrator.id,
        name: narrator.name,
        people: narrator.person && narrator.person.name,
        exact: true
      }
    end)
  end

  defp person_matches(name) do
    Person
    |> where([p], fragment(@name_key_sql, p.name) == ^AutoMatch.person_key(name))
    |> Repo.all()
  end

  ## series

  # When linking to an existing book, a proposed series is only offered if the
  # book doesn't already have it: an import may fill a blank, never overwrite
  # curation.
  defp series_links(records, tags, book_id) do
    records
    |> Enum.flat_map(fn record ->
      record
      |> Map.get("series")
      |> series_proposals()
      |> Enum.map(&Map.put(&1, :source, source_of(record)))
    end)
    |> merge_by_name()
    |> case do
      [] -> series_proposals_from_tags(tags)
      proposed -> proposed
    end
    |> Enum.reject(
      &(already_on_book?(&1.name, book_id) or author_named_series?(&1.name, records, tags))
    )
    |> then(fn kept ->
      Enum.map(
        kept,
        &series_link(&1.name, &1.number || tag_number(&1.name, tags, kept), &1.source)
      )
    end)
  end

  # Goodreads-derived data models an author's whole bibliography as a series
  # named after them, so Joyland arrived in a series called "Stephen King"
  # and Un Lun Dun in one called "China Miéville" — two of ten releases in a
  # real batch, each asking a series question with a junk answer. A series
  # named exactly after a credited author is a shelf, not a series; dropped
  # as a *proposal*, like the reader-created orderings below — the record
  # still says what it said.
  defp author_named_series?(name, records, tags) do
    key = AutoMatch.person_key(name)

    records
    |> proposed_names("authors")
    |> or_from_tags(tags, "authors")
    |> Enum.any?(fn {author, _source} -> AutoMatch.person_key(author) == key end)
  end

  # One series named by two databases is one membership. Whichever of them
  # supplied a number wins, because a number nobody supplied is a question the
  # operator has to answer and this is the cheapest way not to ask it.
  defp merge_by_name(proposals) do
    proposals
    |> Enum.group_by(&down(&1.name))
    |> Map.values()
    |> Enum.map(fn group -> Enum.find(group, List.first(group), & &1.number) end)
    |> Enum.sort_by(fn proposal ->
      Enum.find_index(proposals, &(down(&1.name) == down(proposal.name)))
    end)
  end

  # The file's series number describes this book's position in the series the
  # file names. Applying it to a series the file did NOT name is inventing a
  # fact — safe only when the file named no series at all and there's exactly
  # one proposal for it to have been about.
  defp tag_number(name, tags, proposals) do
    tagged = presence(tags["series"])

    cond do
      is_nil(tagged) and length(proposals) == 1 -> numeric(tags["series_number"])
      tagged && normalize(tagged) == normalize(name) -> numeric(tags["series_number"])
      true -> nil
    end
  end

  # Candidates carry series as `%{"name", "number"}`. Older stored matches
  # carry bare strings, and a rescan is not something to require just to read
  # an item, so both shapes are accepted.
  # Reader-created orderings of a series that already exists — "Legends &
  # Lattes (Chronological)" arriving alongside "Legends & Lattes", which is
  # how Goodreads-derived data models "read these in story order". They are
  # not canon and nobody browses them, but the form proposed them exactly like
  # a real series, so one careless import creates a duplicate series with one
  # book in it. Filtered as a *proposal*: the record still says what it said,
  # and evidence is never edited to make a decision come out differently.
  @order_variant ~r/\(\s*(?:chronological|publication|reading|internal|story)(?:\s+order)?\s*\)\s*$/iu

  defp series_proposals(nil), do: []

  defp series_proposals(entries) when is_list(entries) do
    entries
    |> Enum.map(&series_proposal/1)
    |> Enum.reject(&(is_nil(&1) or Regex.match?(@order_variant, &1.name)))
  end

  defp series_proposals(value) when is_binary(value), do: series_proposals([value])
  defp series_proposals(_other), do: []

  defp series_proposal(%{"name" => name} = entry) when is_binary(name) do
    case presence(name) do
      nil -> nil
      name -> %{name: name, number: numeric(entry["number"]), source: nil}
    end
  end

  defp series_proposal(name) when is_binary(name) do
    case presence(name) do
      nil -> nil
      name -> %{name: name, number: nil, source: nil}
    end
  end

  defp series_proposal(_other), do: nil

  # **A position that isn't a number is not a position.** `book_number` is a
  # decimal column, so `SeriesLink` rightly refuses to store one that won't
  # cast — but proposing it anyway turned a provider quirk into a hard failure
  # with no way out: the draft changeset was invalid, so `RunMatch` failed,
  # retried, and failed again until Oban gave up. The item simply never got a
  # draft, and with no in-app view of background work there was nothing to
  # tell the operator why.
  #
  # Found importing the operator's own `01 Wool [128k]`, where real answers
  # include rreading-glasses' **"1A"** and Hardcover's **"1-5"** — a letter
  # suffix and an omnibus range. Dropped at the *proposal* stage, exactly like
  # the reader-created series orderings: the record still says what it said,
  # and the membership survives with no number, which is already a supported
  # state and an ordinary outstanding decision.
  defp numeric(value) do
    with number when is_binary(number) <- presence(value),
         {_decimal, ""} <- Decimal.parse(number) do
      number
    else
      _not_a_number -> nil
    end
  end

  defp series_proposals_from_tags(tags) do
    case presence(tags["series"]) do
      nil -> []
      name -> [%{name: name, number: numeric(tags["series_number"]), source: "tags"}]
    end
  end

  defp already_on_book?(_name, nil), do: false

  defp already_on_book?(name, book_id) do
    Book
    |> where([b], b.id == ^book_id)
    |> join(:inner, [b], sb in assoc(b, :series_books))
    |> join(:inner, [_b, sb], s in assoc(sb, :series))
    |> where([_b, _sb, s], fragment("lower(?)", s.name) == ^String.downcase(name))
    |> Repo.exists?()
  end

  defp series_link(name, number, source) do
    matches =
      Series
      |> where([s], fragment("lower(?)", s.name) == ^String.downcase(name))
      |> Repo.all()
      |> Enum.map(&%SeriesLink.Match{series_id: &1.id, name: &1.name, exact: true})

    base = %SeriesLink{name: name, number: presence(number), source: source, candidates: matches}

    case matches do
      # A number nobody supplied is a question, not a default. Getting this
      # wrong writes confident nonsense into a curated field.
      _any when number in [nil, ""] ->
        %{base | mode: mode_for(matches), series_id: series_id(matches), approved: false}

      [one] ->
        %{base | mode: :link, series_id: one.series_id, approved: true}

      [] ->
        %{base | mode: :create, approved: provider?(source)}

      _several ->
        %{base | mode: :create, approved: false}
    end
  end

  defp mode_for([_one]), do: :link
  defp mode_for(_other), do: :create

  defp series_id([one]), do: one.series_id
  defp series_id(_other), do: nil

  ## scalars

  # `advisory` is a weaker source: **offered, but never argues.** It shows up
  # as a chip the operator can click, and it is left out of the count that
  # decides whether the sources disagree — so it can rescue a field nobody
  # else answered without turning every field it merely differs from into a
  # question.
  #
  # That distinction is the whole reason it exists. The file's own name is a
  # real third opinion about the title and disagrees with the tags on 105 of
  # the operator's 198 releases; counted as a rival it would put "pick a
  # title" on over half of all imports, for a source that is right a minority
  # of the time. Counted as a proposal, it costs nothing and is one click away
  # exactly when the tags turn out to be a shelf label.
  defp scalar(candidates, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    same? = Keyword.get(opts, :equivalence, &(normalize(&1) == normalize(&2)))
    prefer = Keyword.get(opts, :prefer, fn held, _incoming -> held end)
    alternatives? = Keyword.get(opts, :alternatives, false)

    usable = fn list ->
      list |> List.wrap() |> Enum.reject(&(is_nil(&1) or &1.value in [nil, ""]))
    end

    advisory = opts |> Keyword.get(:advisory) |> usable.()

    deciding =
      candidates
      |> usable.()
      |> collapse(same?, prefer)

    # Nobody else answered, so the advisory one stops being advisory — this is
    # what the old `fallback` did, and the only case where it gets a vote.
    {deciding, advisory} =
      case {deciding, advisory} do
        {[], [first | rest]} -> {[first], rest}
        _primary_had_something -> {deciding, advisory}
      end

    # Shown, but only where it actually adds something: an advisory that means
    # the same as a real proposal is that proposal, not a second chip saying
    # the same words.
    extra = Enum.reject(advisory, fn a -> Enum.any?(deciding, &same?.(&1.value, a.value)) end)

    field = %Field{required: required, candidates: deciding ++ extra}
    candidates = deciding

    case candidates do
      # nothing proposed it. Optional means waived — an explicit "none", which
      # is what makes "every piece resolved" reachable at all.
      [] ->
        %{field | approved: not required}

      # one answer, whether from one source or several that turned out to mean
      # the same thing
      [only] ->
        take(field, only)

      # Several *alternatives* rather than several claims about one fact. Two
      # databases never write the same description, and two cover URLs are two
      # pictures nothing here can compare — calling either "sources disagree"
      # makes the operator arbitrate a non-question on every import. The best
      # record's answer is taken; the rest stay one click away.
      [first | _rest] when alternatives? ->
        take(field, first)

      _several ->
        %{field | approved: false}
    end
  end

  defp take(field, candidate), do: Field.take(field, candidate)

  # Proposals that mean the same thing become one chip, crediting everybody
  # who said it.
  #
  # `same?` is a binary predicate rather than a key function because the
  # interesting equivalences aren't groupable: a year-only date matches any
  # date in that year, but two full dates in that year don't match each other.
  # `prefer` then decides which spelling survives — the cleaner title, the
  # more precise date.
  defp collapse(candidates, same?, prefer) do
    Enum.reduce(candidates, [], fn candidate, kept ->
      case Enum.find_index(kept, &same?.(&1.value, candidate.value)) do
        nil -> kept ++ [candidate]
        index -> List.update_at(kept, index, &combine(&1, candidate, prefer))
      end
    end)
  end

  # `prefer` returns a *value*, so it cannot say which candidate won when both
  # proposed the same one — and comparing its answer to `incoming.value` calls
  # every tie for whoever came last. Records are collected before the file's
  # tags, so a provider and the tags agreeing on a date credited the tags, and
  # the form said "from the file's tags" about a value Hardcover had
  # corroborated. Measured on a real import; provenance is written from this.
  defp combine(held, incoming, prefer) do
    winner =
      if held.value != incoming.value and prefer.(held.value, incoming.value) == incoming.value,
        do: incoming,
        else: held

    # The surviving chip keeps the key it had when it was held, so a choice
    # already made doesn't come unstuck when another source agrees with it.
    %{winner | label: join_labels(held.label, incoming.label), key: held.key}
  end

  defp join_labels(one, one), do: one
  defp join_labels(nil, other), do: other
  defp join_labels(one, nil), do: one
  defp join_labels(one, other), do: "#{one}, #{other}"

  # Two spellings of one title: the shorter is the title, the longer is the
  # title with a format label bolted on.
  defp shorter(held, incoming) do
    if String.length(incoming) < String.length(held), do: incoming, else: held
  end

  defp normalize(string) when is_binary(string) do
    string |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp normalize(other), do: other

  ## candidate helpers

  defp candidate(nil, _key), do: nil

  defp candidate(best, key) do
    case presence(best[key]) do
      nil ->
        nil

      value ->
        %Candidate{
          value: to_string(value),
          source: source_of(best),
          label: label_of(best),
          key: Candidate.key_for(best)
        }
    end
  end

  defp tag_candidate(tags, key) do
    case presence(tags[key]) do
      nil ->
        nil

      value ->
        %Candidate{
          value: to_string(value),
          source: "tags",
          label: "The file's tags",
          key: "tags"
        }
    end
  end

  defp release_candidate(nil), do: nil

  defp release_candidate(value),
    do: %Candidate{
      value: value,
      source: "release_name",
      label: "The release name",
      key: "release_name"
    }

  defp source_of(%{"source" => source}), do: source
  defp source_of(_other), do: nil

  defp label_of(%{"provider_name" => name}) when is_binary(name), do: name
  defp label_of(%{"source" => "local"}), do: "Already in the library"
  defp label_of(%{"source" => source}), do: source
  defp label_of(_other), do: nil

  defp provider?("provider:" <> _rest), do: true
  defp provider?(_other), do: false

  defp names(nil), do: nil
  defp names([]), do: nil
  defp names(list) when is_list(list), do: list |> Enum.map(&presence/1) |> Enum.reject(&is_nil/1)
  defp names(value) when is_binary(value), do: [value]
  defp names(_other), do: nil

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(other), do: other
end
