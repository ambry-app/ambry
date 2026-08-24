defmodule Ambry.Inbox.Draft.Seed do
  @moduledoc """
  Builds a draft from what an item's files and providers had to say.

  Seeding is where the auto-approval rules live, and they share one logic: a
  rule may settle a decision only when getting it wrong would be *cheap*,
  because the answer is identity rather than similarity or because there was
  only one answer on offer. Everything else is left for a human.

    * **work identity** — only ever "is this a book you already have". A close
      local match settles it as that book; a weaker one is offered and never
      assumed. No local hit settles it as a new book.
    * **recording identity** — settled by an ASIN or a confident match, and
      settled when nothing was found at all, since plenty of good rips are in
      no storefront. A doubted match settles nothing and records why.
    * **scalar** — nothing proposed and optional: waived. One proposal, or
      several agreeing once normalized: taken. Several that disagree: the
      operator's. Format labels are not a disagreement.
    * **credit** — one exact identity match: linked. No match at all, from a
      provider-matched work: created. A *Person* matches but the identity
      does not: always the operator's, because "is this the same human?" is
      the judgment not to automate.
    * **new credit from tags, never automatically**, because tag names come
      from imperfect multi-value splitting ("Sanderson, Brandon").
    * **series number** — never invented, but every provider reports one. A
      tag's number belongs to the series the tag named.

  Choosing a different candidate refills the fields from it (`reseed_work/4`,
  `reseed_recording/4`); anything the operator typed survives.
  """

  import Ambry.Inbox.AutoMatch, only: [person_key_sql: 1]
  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.GroupLink
  alias Ambry.Inbox.Draft.PersonDecision
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.SourceRef
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Library
  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ambry.Media
  alias Ambry.Media.Media.Chapter
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  # How closely an existing Book has to match before the import proposes
  # linking to it. Deliberately high: attaching a recording to the wrong book
  # is worse than one duplicate Book and much harder to notice.
  @strong_local 0.95

  # How sure a recording match must be before its metadata is allowed to
  # describe this file.
  @trusted_recording 0.75

  # The same for a work, lower than the recording's bar: a wrong work is a
  # visibly wrong title on the form.
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
      replacement: replacement(item),
      work: work,
      recording: recording(recording_level, hints, tags, item),
      destination: destination(item)
    }
    |> reseed_people(item)
    |> seed_group(item)
  end

  @doc """
  Proposes the recording's place in a part set, or leaves the operator's
  answer alone.

  Detection reads the release's own name first, the tag title's tail second,
  and the ticked records' titles third. A proposal is never auto-approved, so
  the common case is one Confirm.

  Curated, removed and operator-added links survive untouched.
  """
  def seed_group(%Draft{recording: nil} = draft, _item), do: draft

  def seed_group(%Draft{} = draft, %InboxItem{} = item) do
    existing = draft.recording.recording_group

    if existing && (existing.curated or existing.removed or existing.source == "manual") do
      draft
    else
      put_in(
        draft,
        [Access.key(:recording), Access.key(:recording_group)],
        propose_group(draft, item)
      )
    end
  end

  # A single existing group proposes a `:link` even when nothing in the
  # release says "part": having one is itself the question. Several ride
  # along as candidates on an unresolved `:create`.
  defp propose_group(draft, item) do
    detected = detect_part(draft, item)

    case {detected, book_groups(draft)} do
      {nil, []} -> nil
      {_detected, [group]} -> link_proposal(group, detected)
      {detected, groups} -> create_proposal(draft, detected, groups)
    end
  end

  defp link_proposal(group, detected) do
    {number, total, source} = detected || {nil, nil, nil}

    %GroupLink{
      mode: :link,
      recording_group_id: group.id,
      name: group.name,
      proposed_name: group.name,
      part_number: number,
      parts_total: group.parts_total || total,
      source: source || "local",
      approved: false,
      candidates: group_candidates([group])
    }
  end

  defp create_proposal(draft, detected, groups) do
    {number, total, source} = detected || {nil, nil, nil}
    name = proposed_group_name(draft.recording)

    %GroupLink{
      mode: :create,
      name: name,
      proposed_name: presence(name),
      source: source || "local",
      part_number: number,
      parts_total: total,
      approved: false,
      candidates: group_candidates(groups)
    }
  end

  defp group_candidates(groups) do
    Enum.map(groups, fn group ->
      %GroupLink.Match{
        recording_group_id: group.id,
        name: group.name,
        parts_total: group.parts_total
      }
    end)
  end

  defp book_groups(%Draft{work: %Work{mode: :link, book_id: book_id}}) when not is_nil(book_id),
    do: Ambry.Media.recording_groups_for_book(book_id)

  defp book_groups(_draft), do: []

  # A group's name distinguishes this set from the book's other recordings,
  # which is the production, and the publisher is that fact. Blank when
  # nobody knows.
  defp proposed_group_name(%Recording{publisher: %Field{} = publisher}) do
    Field.value(publisher) ||
      case publisher.candidates do
        [%Candidate{value: value} | _rest] when is_binary(value) -> value
        _none -> ""
      end
  end

  defp proposed_group_name(_recording), do: ""

  defp detect_part(draft, item) do
    parsed = ReleaseName.parse(item.path)
    tag_parsed = ReleaseName.parse((item.tags || %{})["book_title"] || "")

    cond do
      is_integer(parsed.parts_total) ->
        {parsed.part_number, parsed.parts_total, "release_name"}

      is_integer(tag_parsed.parts_total) ->
        {tag_parsed.part_number, tag_parsed.parts_total, "tags"}

      part = provider_part(draft, item) ->
        part

      true ->
        nil
    end
  end

  defp provider_part(draft, item) do
    item
    |> records("recording")
    |> used(draft.recording.sources)
    |> Enum.find_value(fn record ->
      case ReleaseName.part_of(record["title"]) do
        nil -> nil
        {number, total} -> {number, total, source_of(record)}
      end
    end)
  end

  @doc """
  Marks a draft as built against evidence that has since changed.

  Discovery must never rewrite a curated choice, so a file that moved makes
  the draft say so rather than silently re-seeding.
  """
  def restale(nil, _item), do: nil

  def restale(%Draft{} = draft, %InboxItem{} = item) do
    %{draft | stale: draft.evidence != evidence(item)}
  end

  # A draft is built against the files *in the recording* and their probe, so
  # a rename, a replacement or an exclusion all show up here.
  defp evidence(%InboxItem{} = item) do
    :erlang.phash2({InboxItem.included(item), item.probe}) |> Integer.to_string()
  end

  ## replacement

  @doc """
  A replacement decision with nothing chosen: the path evidence, or `:new`.
  """
  def replacement(%InboxItem{} = item), do: repropose(%Replacement{}, item)

  @doc """
  Re-derives an unanswered replacement decision from the path evidence.

  Discovery does not hide a file a recording was imported from, so the
  provenance proposes this decision instead. A proposal is never approved:
  the files turning up again is evidence, and replacing is the operator's
  call.

  An answered decision is left alone, which is what `curated` is for.
  """
  def repropose(%Replacement{curated: true} = replacement, _item), do: replacement

  def repropose(%Replacement{} = replacement, %InboxItem{} = item) do
    item = Repo.preload(item, :source)

    case Media.imported_from(InboxItem.disk_files(item)) do
      {:ok, media} -> %{replacement | mode: :replace, media_id: media.id, approved: false}
      :none -> %{replacement | mode: :new, media_id: nil, approved: true}
    end
  end

  ## destination

  @doc """
  A destination with nothing chosen: pure defaults.
  """
  def destination(%InboxItem{} = item), do: redefault(%Destination{}, item)

  @doc """
  Fills in whichever halves of a destination the operator hasn't picked.

  The root is chosen per import and the policy follows from the **pairing**
  rather than either end, which is why this runs again after a root is picked.

  Everything not chosen is recomputed on every prepare, so correcting the
  first of a batch corrects the rest with it.
  """
  def redefault(%Destination{} = destination, %InboxItem{} = item) do
    item = Repo.preload(item, :source)
    roots = Library.list_roots()

    root =
      if destination.root_chosen,
        # Filtered through the current registry: a root can be deleted
        # between the choice and this.
        do: find_root(roots, destination.root_id),
        else: default_root(item.source, roots)

    policy =
      cond do
        destination.policy_chosen -> destination.policy
        is_nil(root) -> nil
        true -> default_policy(item.source, root)
      end

    %{destination | root_id: root && root.id, policy: policy}
  end

  # Where this source last imported, then the only root there is: being asked
  # to pick from a list of one is an interruption, not a decision.
  defp default_root(%Source{} = source, roots) do
    remembered = Library.recall_placement(source)

    find_root(roots, remembered && remembered.library_root_id) ||
      case roots do
        [only] -> only
        _none_or_several -> nil
      end
  end

  defp find_root(_roots, nil), do: nil
  defp find_root(roots, id), do: Enum.find(roots, &(&1.id == id))

  # What this exact pairing last did, and failing that what the disk allows.
  defp default_policy(%Source{} = source, %Root{} = root) do
    Library.recall_policy(source, root) || feasible_policy(source, root)
  end

  # Sharing a filesystem, hardlink dominates: no extra bytes, source
  # untouched, nothing to dangle. Across filesystems the three remaining doors
  # mean genuinely different things and guessing wrong silently doubles the
  # operator's storage, so nothing is proposed.
  defp feasible_policy(%Source{} = source, %Root{} = root) do
    case Library.same_filesystem?(source.path, root.path) do
      {:ok, true} -> :hardlink
      _different_or_unknown -> nil
    end
  end

  ## work

  # The first decision is "is this a book you already have", not "which of
  # these records": linking creates nothing and inherits the book's curation.
  defp work(level, hints, tags, item) do
    records = records(level)
    local = Map.get(level, "local", []) || []
    confidence = Map.get(level, "confidence")

    {mode, book_id, approved} = work_identity(local)

    # Only a work we believe in fills anything in: fields that look settled
    # and are wrong are worse than fields that are visibly empty.
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

  # A candidate's score and the decision's confidence are different numbers,
  # since confidence sinks when rivals score nearly as well.
  defp weak_work_detail(best, confidence) do
    doubt_detail(best, confidence, "#{best["title"]}#{written_by(best["authors"])}", "book")
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
  typed survives.
  """
  def reseed_work(%Work{} = work, %InboxItem{} = item) do
    work
    |> follow_query(item, "work")
    |> put_work_fields(records(item, "work"), AutoMatch.hints(item), item.tags || %{}, item)
  end

  # A query is evidence, not a decision, so it follows the latest match, or
  # the evidence header reports an older search than the records below it.
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

    # A linked book is not edited by an import, so nothing about it is a
    # decision, series included.
    series =
      if work.mode == :link,
        do: [],
        else: keep_curated(work.series, series_links(sources, tags))

    %{
      work
      | title: keep_manual(work.title, title_field(sources, hints, tags)),
        published: keep_manual(work.published, published_field(sources, tags)),
        authors: keep_curated(work.authors, author_credits(sources, tags)),
        series: series
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

  # A field value is cheap to recompute; a credit is not. Fresh proposals
  # nothing curated covers are appended, so ticking a record still brings its
  # people in.
  defp keep_curated(existing, fresh) do
    curated = Enum.filter(existing, & &1.curated)
    taken = MapSet.new(curated, &down(&1.name || ""))

    curated ++ Enum.reject(fresh, &MapSet.member?(taken, down(&1.name || "")))
  end

  # A field the operator typed is theirs, but the candidates still follow the
  # fresh derivation: curation protects decisions, not evidence.
  defp keep_manual(%Field{source: "manual"} = existing, fresh),
    do: %{existing | candidates: fresh.candidates}

  # A picked chip stays picked while its proposal is on offer. Gated on
  # `curated`, never on `chosen_key`, which the seeder sets too.
  defp keep_manual(%Field{curated: true} = existing, fresh) when is_binary(existing.chosen_key) do
    # By key first, then by value: a key can legitimately disappear while
    # the answer stays on offer, when a picked chip is later dropped as a
    # duplicate of a ticked record's identical title.
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

  # A convincing local hit proposes a link, which is what stops a second
  # recording splitting a work. "Create" is the absence of an existing book,
  # not a separate answer.
  defp work_identity(local) do
    case Enum.max_by(local, &(&1["score"] || 0.0), fn -> nil end) do
      %{"id" => id, "score" => score} when score >= @strong_local ->
        {:link, id, true}

      %{} ->
        # Close enough to show but not to assume: attaching a recording to
        # the wrong existing book is worse than creating one too many.
        {:create, nil, false}

      # Nothing in the library could be this book, so it isn't a question.
      # Asking anyway strands the operator: the control only renders when
      # there ARE local candidates.
      nil ->
        {:create, nil, true}
    end
  end

  # The release name is a fallback, not a peer: roughly 96% of releases carry
  # a title in tags, so letting the folder name argue with a provider would
  # make nearly every import ambiguous on its title.
  #
  # But it is a third opinion and has to be on offer. The two disagree on more
  # than half of an ordinary library's releases, and for a meaningful minority
  # the name is the one telling the truth — a file tagged with a shelf label
  # and named with the real title.
  #
  # Offered rather than preferred: the name rescues a shelf-labelled tag and
  # is catastrophic elsewhere, and which is right is a judgement.
  defp title_field(sources, hints, tags) do
    (from_records(sources, "title") ++ [tag_candidate(tags, "book_title")])
    |> scalar(
      required: true,
      equivalence: &same_title?/2,
      prefer: &shorter/2,
      advisory: release_candidate(hints.release_title)
    )
  end

  # A title and that same title carrying a subtitle are one answer written
  # two ways. The dominant tag shape is `Title: Series, Book N` while the
  # catalogues answer with the bare title, so scored as rivals they put "pick
  # a title" on a large share of imports.
  #
  # Asymmetric containment, not a shared prefix: one title has to be the
  # *whole* of the other's head.
  #
  #     "Battle Ground: The Dresden Files, Book 17" ≡ "Battle Ground"
  #     "The Expanse: Leviathan Wakes"              ≢ "The Expanse: Caliban's War"
  #     "Dune"                                     ≢ "Dune Messiah"
  #
  # The last one is why word-prefix containment is not enough: a subtitle is
  # separated by punctuation. `prefer: &shorter/2` then keeps the bare title.
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

  # Storefront titles carry the format label and work-level providers do not,
  # so only format labels are set aside, and only for equivalence: both
  # strings stay in the candidate list and the shorter wins the field.
  #
  # "Dramatized Adaptation" and "(1 of 3)" name a genuinely different
  # recording and are not stripped.
  @format_labels ~r/\b(?:un)?abridged(?:\s+edition)?\b|\baudio\s?book\b|\baudio\s+edition\b/iu

  # A trailing *labelled* ordinal (", Vol. 1") is the same title, since one
  # catalogue writes it where another writes the bare title. A bare trailing
  # number is part of the title and stays.
  @trailing_ordinal ~r/,?\s+(?:book|bk\.?|vol\.?|volume)\s+\d+(?:\.\d+)?\s*$/i

  defp title_key(value) when is_binary(value) do
    value
    |> String.replace(@trailing_ordinal, " ")
    |> String.replace(@format_labels, " ")
    # a bracket that held nothing but a format label is now empty
    |> String.replace(~r/[(\[{]\s*[)\]}]/u, " ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> normalize()
    # A leading article is not a different title.
    |> String.replace(~r/^(the|a|an)\s+/u, "")
  end

  defp title_key(other), do: normalize(other)

  # Year-only knowledge arrives as a literal January 1st, from providers and
  # file tags alike: "2017-01-01" and "2017-10-03" are one fact at two
  # precisions, and the precise one is the answer.
  #
  # Two precise dates in one year genuinely do disagree, and so do two
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

  # The file's date tag is not an opinion about *which* date it is. Audiobook
  # files carry exactly one in practice, filled from whichever year the tagger
  # had to hand, so where a copyright line separates the text's © year from
  # the recording's ℗ year the tag holds either about equally often.
  #
  # So it is advisory at both levels: offered as a chip, never counted in the
  # disagreement, promoted only where nothing else proposed one.
  defp published_field(sources, tags) do
    sources
    |> from_records("published")
    |> scalar(
      required: true,
      equivalence: &same_date?/2,
      prefer: &more_precise/2,
      advisory: [tag_candidate(tags, "published")]
    )
  end

  ## recording

  defp recording(level, hints, tags, item) do
    records = records(level)

    # Only a recording we believe in fills anything in: a storefront widens a
    # narrow query, so a book whose only catalogued edition has a different
    # reader still returns it. A doubted record stays in the list, untricked.
    {doubt, detail, best} = trust(records, level, hints)

    %Recording{
      confidence: Map.get(level, "confidence"),
      query: Map.get(level, "query"),
      query_fields: Map.get(level, "query_fields") || %{},
      doubt: doubt,
      doubt_detail: detail,
      # `settled_group/1`, not `top_group/1`: once the file has named its
      # reader, a record naming none is a poor thing to adopt fields from.
      sources:
        if(best, do: Enum.map(AutoMatch.settled_group(records), &SourceRef.of/1), else: []),
      # Settled on a trusted match, or where there was nothing to choose
      # between. A doubted record leaves the question open.
      approved: doubt in [:none, :nothing_found],
      chapters: file_chapters(item)
    }
    |> put_recording_fields(records, tags, item)
  end

  @doc """
  The chapter list, exactly as the probe read it off the files.

  Seeded approved, since the file's own answer is the lone proposer. nil
  until a probe has run, so "not read yet" stays distinguishable from "the
  files carry no chapters".
  """
  def file_chapters(%InboxItem{probe: %{"chapter_list" => rows} = probe}) when is_list(rows) do
    %Chapters{
      chapter_marker_source: marker_source(probe["chapter_marker_source"]),
      approved: true,
      curated: false,
      chapters: Enum.map(rows, &chapter_row/1)
    }
  end

  def file_chapters(_item), do: nil

  defp chapter_row(row) do
    %Chapter{
      time: row["time"] && Decimal.new(row["time"]),
      title: row["title"],
      title_source: title_source(row["title_source"])
    }
  end

  defp marker_source("embedded"), do: :embedded
  defp marker_source("file_boundaries"), do: :file_boundaries
  defp marker_source("manual"), do: :manual
  defp marker_source(_unrecorded), do: nil

  defp title_source("embedded"), do: :embedded
  defp title_source("filename"), do: :filename
  defp title_source("provider"), do: :provider
  defp title_source("generated"), do: :generated
  defp title_source("manual"), do: :manual
  defp title_source(_unrecorded), do: nil

  @doc """
  Re-derives a recording's fields from whichever records are currently ticked.
  """
  def reseed_recording(%Recording{} = recording, %InboxItem{} = item) do
    recording
    |> follow_query(item, "recording")
    |> put_recording_fields(records(item, "recording"), item.tags || %{}, item)
  end

  # Only records of this recording describe this recording. A work record's
  # publisher printed the book, its description is the print blurb rather
  # than the performance, and its cover is a portrait print jacket where
  # audiobook art is square.
  #
  # A database's audio editions answer all three and arrive as recording
  # records; reaching through to the book where an edition is thin is the
  # adapter's job.
  defp put_recording_fields(%Recording{} = recording, records, tags, item) do
    mine = used(records, recording.sources)

    # The release date is where the file's date tag belongs if it belongs
    # anywhere (see `published_field/2`); without it a recording no provider
    # catalogues imports with no date at all. `same_date?` is what stops
    # "2012" and "2012-03-23" reading as rival answers.
    published =
      keep_manual(
        recording.published,
        scalar(from_records(mine, "published"),
          equivalence: &same_date?/2,
          prefer: &more_precise/2,
          advisory: [tag_candidate(tags, "published")]
        )
      )

    %{
      recording
      | title: keep_manual(recording.title, scalar([], required: false)),
        published: published,
        publisher:
          keep_manual(
            recording.publisher,
            scalar(from_records(mine, "publisher") ++ [tag_candidate(tags, "publisher")])
          ),
        # Two databases never write the same description, and two cover URLs
        # cannot be compared without fetching them, so one is taken and the
        # rest stay one click away.
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

  # An ASIN hit is identity and needs no corroboration. Otherwise the
  # narrator decides: a candidate naming a different reader is the wrong
  # recording of the right book.
  #
  # Returns *why* it isn't trusted as well as whether: "no provider listed
  # this" and "a provider listed a different reader" call for different things.
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
    doubt_detail(best, confidence, "#{best["title"]}#{narrated_by(best["narrators"])}", "file")
  end

  # Shared by the work and recording doubts; `what` is "book" or "file".
  defp doubt_detail(best, confidence, described, what) do
    score = round((best["score"] || 0.0) * 100)
    conf = round(confidence * 100)
    lead = "The closest is #{described} at #{score}%"

    if conf < score - 5 do
      lead <>
        ", but other candidates score nearly as well. Only #{conf}% sure overall, " <>
        "not enough to describe this #{what} unconfirmed."
    else
      lead <> ", not a close enough match to describe this #{what}."
    end
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

  # Embedded art and a provider cover are both real answers, so two of them
  # is a choice rather than a winner. The embedded candidate carries the audio
  # file to extract from, resolved to a disk path for the extractor.
  defp cover_field(sources, tags, item) do
    embedded =
      if tags["has_cover_art"] && InboxItem.included(item) != [] do
        %Candidate{
          value: item |> Repo.preload(:source) |> InboxItem.disk_files() |> List.first(),
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

  # A cast label is not a person to create. Where a record is ticked its real
  # cast supplies the credits; this is for where nothing is.
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

  For when the library moved under a queued item. Deliberately not a re-seed,
  which would re-open answered questions.

  It changes one thing in one direction: something that meant to **create**
  and now finds exactly one thing of that name becomes a **link** to it.
  Approval, values, chips and curation are left alone.

  Curated decisions are skipped, and an *ambiguous* result (two identities of
  one name) is left alone: that is a real question.
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
    # Once `relink_work` flips a sibling's work to a book that now exists,
    # the same pass sees that book's group and upgrades an uncurated `:create`
    # to "join the existing set". Curated links pass through untouched, so
    # re-running relink is idempotent.
    |> seed_group(item)
    |> reconcile_people(item)
    |> reopen_new_person_questions()
  end

  # The one case where relink *reopens* a question rather than resolving one.
  # A credit auto-approves on the premise "nobody by that name at all", which
  # a sibling import can invalidate: one import creates the person, and the
  # next item's credit for a *different identity* of theirs would sail through
  # and create them a second time. The seeder never automates "is this the
  # same human?", so this may not either, and the credit goes back to
  # unapproved. Curated credits stay put, so answering it once is final.
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
  # and the second still says "create". A work settled as new whose title now
  # matches exactly one Book with an overlapping author becomes a link to it,
  # and its fields are re-derived for link mode, with `keep_manual` and
  # `keep_curated` holding every answered question.
  #
  # Anything short of exactly-one-with-matching-author is left alone: linking
  # a recording to the wrong existing book is the worst outcome this form can
  # produce.
  defp relink_work(%Draft{work: %Work{mode: :create, curated: false} = work} = draft, item) do
    with title when is_binary(title) <- relink_title(work),
         [book] <- books_titled(title),
         true <- authors_overlap?(book, work) do
      linked = %{work | mode: :link, book_id: book.id, approved: true}
      %{draft | work: reseed_work(linked, item)}
    else
      _no_single_certain_match -> draft
    end
  end

  defp relink_work(draft, _item), do: draft

  # A settled value when there is one, else the leading proposal: a title
  # whose candidates merely disagree on spelling has no value yet, and the
  # title-key and author-overlap guards below do the real vetting. Without it
  # a split release's sibling relink silently never fires.
  defp relink_title(%Work{title: %Field{} = title}) do
    Field.value(title) ||
      case title.candidates do
        [%Candidate{value: value} | _rest] when is_binary(value) -> value
        _none -> nil
      end
  end

  defp relink_title(_work), do: nil

  # Fetched by keyword and filtered on `title_key/1`: exact identity, but
  # case, punctuation and leading articles do not make a different book. Two
  # releases titled "Princess Bride" and "The Princess Bride" are one book,
  # and a `lower(=)` comparison leaves the twin unlinked over the article.
  defp books_titled(title) do
    key = AutoMatch.title_key(title)

    title
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
  # as it is. `reseed_people/2` *rebuilds* the uncurated ones, which is right
  # after a record tick and wrong here, where it would re-open a person the
  # operator had settled.
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
      # Exactly one identity of this name now exists: the seeder's own rule,
      # run against facts it did not have. The person reference goes with it,
      # since a linked identity already has its human.
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
    case matching_series(name) do
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

  # Fetched whole and compared by `same_series?/2` rather than a `lower(=)`:
  # the table is small, and an exact comparison files one series under two
  # names, or three once an accent variant appears.
  defp matching_series(name) do
    Series
    |> Repo.all()
    |> Enum.filter(&AutoMatch.same_series?(&1.name, name))
  end

  @doc """
  Brings the draft's people into line with whoever the credits now reference.

  Runs after every change that can move a credit, as one function rather than
  seed-time and edit-time copies.

  **A curated person keeps their decisions, not their evidence.** Skipping
  them wholesale would make "look again" show nothing new for exactly the
  people the button exists for, since renaming somebody is what marks them
  curated. Their candidate lists rebuild like everyone else's, and
  `keep_manual/2` pins whatever the operator settled.
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

  # An untouched person is rebuilt wholesale, but a field settled inside one
  # survives: picking a photo curates the *field*, not the person.
  defp keep_person_fields(nil, fresh), do: fresh

  defp keep_person_fields(%PersonDecision{} = was, fresh) do
    %{
      fresh
      | name: keep_manual(was.name, fresh.name),
        image: keep_manual(was.image, fresh.image),
        description: keep_manual(was.description, fresh.description)
    }
  end

  # Matched against what the person is called *now*, not what the credit
  # says: the credit holds the pen name, and a rename is precisely when
  # somebody searches again. Mode, link, approval, settled fields and a
  # curated tick set all stay the operator's.
  defp refreshed_person(%PersonDecision{} = person, named, matched) do
    {credited, source} = named || {person.key, nil}
    name = Field.value(person.name) || credited
    candidates = named_candidates(matched, name)
    {doubt, detail} = person_doubt(matched, candidates, name)

    {sources, pool} =
      if person.evidence_curated,
        do: {person.sources, ticked_candidates(matched, person.sources)},
        else: {Enum.map(candidates, &SourceRef.of/1), candidates}

    %{
      person
      | doubt: doubt,
        doubt_detail: detail,
        sources: sources,
        name: keep_manual(person.name, person_name_field(credited, source, pool)),
        image: keep_manual(person.image, person_image_field(pool)),
        description: keep_manual(person.description, person_description_field(pool))
    }
  end

  @doc """
  Re-derives a person's photo and bio pools from their ticked records.

  Ticking a record is what makes it speak — the same rule the work and
  recording levels live by. The exact-name gate decides the initial ticks;
  from there the operator's checkbox does, which is also how a
  differently-spelled record of the right human (the gate can't admit it)
  gets to contribute a face after all.
  """
  def rederive_person_evidence(%PersonDecision{} = person, matched) do
    pool = ticked_candidates(matched, person.sources)

    %{
      person
      | image: keep_manual(person.image, person_image_field(pool)),
        description: keep_manual(person.description, person_description_field(pool))
    }
  end

  defp ticked_candidates(matched, sources) do
    candidates = (matched && Map.get(matched, "candidates")) || []

    Enum.filter(candidates, fn record -> Enum.any?(sources, &SourceRef.points_at?(&1, record)) end)
  end

  # Taken from the credit that references them, which is the only thing that
  # knows: a key is a normalised string and a record may spell it differently.
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
      # Same bar the credit clears. A person nobody was found for has nothing
      # left to decide beyond the name; one the *wrong* people were found for
      # does.
      approved: provider?(source) and doubt != :low_confidence
    }
  end

  # Only records actually about this human may propose anything: person
  # search is recall-first, which is right for a grid a human reads and wrong
  # for a field's candidate list.
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

      # Found people, none of them this one: the difference from "nothing
      # found" is whether looking again is likely to help.
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
          key: Candidate.key_for(candidate),
          record: candidate["id"] && to_string(candidate["id"])
        }
      end)
    )
    |> scalar(required: true, alternatives: true)
  end

  # Every photo every database has: the job is not "find a photo" but "find
  # one that survives a circular crop". One candidate per image.
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

  # Three databases' prose about one person are alternatives, never a
  # disagreement to arbitrate.
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

  # Providers return these where they have no biography. Storing one as
  # somebody's life story is worse than blank: blank is visibly unfinished.
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

    base = %Credit{
      name: name,
      proposed_name: name,
      kind: kind,
      source: source,
      candidates: matches
    }

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

  defp identity_matches(name, :author) do
    Author
    |> where([a], person_key_sql(a.name) == ^AutoMatch.person_key(name))
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
    |> where([n], person_key_sql(n.name) == ^AutoMatch.person_key(name))
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
    |> where([p], person_key_sql(p.name) == ^AutoMatch.person_key(name))
    |> Repo.all()
  end

  ## series

  defp series_links(records, tags) do
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
    |> Enum.reject(&author_named_series?(&1.name, records, tags))
    |> then(fn kept ->
      Enum.map(
        kept,
        &series_link(&1.name, &1.number || tag_number(&1.name, tags, kept), &1.source)
      )
    end)
  end

  # Some catalogues model an author's whole bibliography as a series named
  # after them, so a standalone novel arrives in a series called by its
  # author's name, and every such release asks a series question with a junk
  # answer. A series named exactly after a credited author is a shelf, not a
  # series; dropped as a *proposal*, like the reader-created orderings below,
  # so the record still says what it said.
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
  # Grouped by `same_series?/2`, not by exact name: "Bill Hodges" and "Bill
  # Hodges Trilogy" are one series spelled two ways, and grouping on the exact
  # string files those books under both, plus a third membership from an
  # accent variant. Same family as titles: dots, fillers, accents and
  # subtitles are spellings, not different series.
  defp merge_by_name(proposals) do
    proposals
    |> Enum.reduce([], fn proposal, groups ->
      case Enum.find_index(groups, fn [held | _rest] ->
             AutoMatch.same_series?(held.name, proposal.name)
           end) do
        nil -> groups ++ [[proposal]]
        index -> List.update_at(groups, index, &(&1 ++ [proposal]))
      end
    end)
    |> Enum.map(fn group -> Enum.find(group, List.first(group), & &1.number) end)
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
  # with no way out: the draft changeset is invalid, so `RunMatch` fails,
  # retries, and fails again until Oban gives up. The item never gets a draft,
  # and nothing tells the operator why.
  #
  # Real answers include **"1A"** and **"1-5"**: a letter suffix and an
  # omnibus range. Dropped at the *proposal* stage, exactly like
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

  defp series_link(name, number, source) do
    matches =
      name
      |> matching_series()
      |> Enum.map(&%SeriesLink.Match{series_id: &1.id, name: &1.name, exact: true})

    base = %SeriesLink{
      name: name,
      proposed_name: name,
      number: presence(number),
      source: source,
      candidates: matches
    }

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
  # real third opinion about the title and disagrees with the tags on better
  # than half of an ordinary library's releases; counted as a rival it would
  # put "pick a title" on most imports, for a source that is right a minority
  # of the time. Counted as a proposal, it costs nothing and is one click
  # away
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

    # Nobody else answered, so the advisory one stops being advisory. This is
    # the only case where it gets a vote.
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
  # proposed the same one, and comparing its answer to `incoming.value` calls
  # every tie for whoever came last. Records are collected before the file's
  # tags, so a provider and the tags agreeing on a date would credit the tags,
  # and the form would say "from the file's tags" about a value a provider had
  # corroborated. Provenance is written from this.
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

  # Two spellings of one title. The junk-free spelling wins first ("Artemis"
  # over "Artemis (Unabridged)"), and this arm must come before the caps
  # tie-break, which would otherwise prefer the junk-carrying spelling because
  # "(Unabridged)" adds a capital. Then a *head* reduction (a subtitle bolted
  # on) prefers the bare title, and same-word spellings (an article, casing)
  # prefer the better-cased one, since a tag reading "house in the cerulean
  # sea" is the same title as a catalogue's proper casing.
  defp shorter(held, incoming) do
    cond do
      junky?(held) and not junky?(incoming) -> incoming
      junky?(incoming) and not junky?(held) -> held
      head_reduction?(held, incoming) -> incoming
      head_reduction?(incoming, held) -> held
      caps(incoming) > caps(held) -> incoming
      true -> held
    end
  end

  defp junky?(value) when is_binary(value) do
    Regex.match?(@format_labels, value) or Regex.match?(@trailing_ordinal, value)
  end

  defp junky?(_other), do: false

  defp head_reduction?(long, short) when is_binary(long) and is_binary(short) do
    title_key(long) != title_key(short) and title_head(long) == title_key(short)
  end

  defp head_reduction?(_long, _short), do: false

  defp caps(value) when is_binary(value) do
    value |> String.graphemes() |> Enum.count(&(&1 != String.downcase(&1)))
  end

  defp caps(_other), do: 0

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
          key: Candidate.key_for(best),
          record: best["id"] && to_string(best["id"]),
          format:
            (key == "published" && Candidate.date_format(value, best["published_format"])) ||
              nil
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
          key: "tags",
          format:
            (key == "published" &&
               Candidate.date_format(value, presence(tags["published_format"]))) ||
              nil
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
