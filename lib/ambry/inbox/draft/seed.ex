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

    * **work identity** — auto on ASIN identity, an exact local title+author
      match, or a top score ≥ 0.90 whose runner-up is ≤ 0.70. Local books
      already outrank equal provider hits in `AutoMatch`, so "reuse the work"
      wins by default.
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

  alias Ambry.Books.Book
  alias Ambry.Books.Series
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Candidate
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.SeriesLink
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library
  alias Ambry.Library.Location
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.People.Person
  alias Ambry.Repo

  @strong_match 0.90
  @weak_runner_up 0.70

  # How sure a recording match must be before its metadata is allowed to
  # describe this file.
  @trusted_recording 0.75

  @doc """
  Builds a fresh draft for an item from its matches, tags and release name.
  """
  def build(%InboxItem{} = item) do
    hints = AutoMatch.hints(item)
    tags = item.tags || %{}
    matches = item.matches || %{}

    work_level = Map.get(matches, "work", %{})
    recording_level = Map.get(matches, "recording", %{})

    %Draft{
      evidence: evidence(item),
      stale: false,
      work: work(work_level, hints, tags),
      recording: recording(recording_level, hints, tags, item),
      destination: destination(item)
    }
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

  defp work(level, hints, tags) do
    candidates = Map.get(level, "candidates", []) || []
    best = List.first(candidates)
    confidence = Map.get(level, "confidence")

    {mode, book_id, approved} = work_identity(candidates, confidence)

    %Work{
      mode: mode,
      book_id: book_id,
      approved: approved,
      candidates: candidates,
      confidence: confidence,
      query: Map.get(level, "query"),
      query_fields: Map.get(level, "query_fields") || %{},
      selected_source: best && best["source"],
      selected_id: best && to_string(best["id"])
    }
    |> put_work_fields(best, hints, tags)
  end

  @doc """
  Fills a work's fields from one candidate, keeping anything the operator
  typed.

  This is what makes the candidate list a question rather than a display: a
  release is a recording of exactly one work, so picking a different candidate
  has to change what the book will say. Manual edits survive, because 1d's
  whole point is that curation outranks any source.
  """
  def reseed_work(%Work{} = work, candidate, hints, tags) do
    %{
      work
      | mode: if(candidate["source"] == "local", do: :link, else: :create),
        book_id: if(candidate["source"] == "local", do: candidate["id"]),
        approved: true,
        selected_source: candidate["source"],
        selected_id: to_string(candidate["id"])
    }
    |> put_work_fields(candidate, hints, tags)
  end

  @doc """
  Detaches a work from every candidate — a book nothing matched, described by
  the file alone.
  """
  def reseed_new_work(%Work{} = work, hints, tags) do
    %{
      work
      | mode: :create,
        book_id: nil,
        approved: true,
        selected_source: nil,
        selected_id: nil
    }
    |> put_work_fields(nil, hints, tags)
  end

  defp put_work_fields(%Work{} = work, best, hints, tags) do
    book_id = if best && best["source"] == "local", do: best["id"]

    %{
      work
      | title: keep_manual(work.title, title_field(best, hints, tags)),
        published: keep_manual(work.published, published_field(best, tags)),
        published_format: keep_manual(work.published_format, published_format_field(best, tags)),
        authors: author_credits(best, tags),
        series: series_links(best, tags, book_id)
    }
  end

  # A field the operator typed is theirs; re-seeding from another candidate
  # must not quietly undo a correction. Everything else is provider data being
  # replaced by other provider data, which is exactly what was asked for.
  defp keep_manual(%Field{source: "manual"} = existing, _fresh), do: existing
  defp keep_manual(_existing, fresh), do: fresh

  # An existing Book is the best outcome there is — it's what stops a second
  # recording of a work splitting the library — so a confident local hit links
  # rather than creating a near-duplicate.
  defp work_identity([], _confidence), do: {:create, nil, false}

  defp work_identity([best | rest], confidence) do
    strong? = strong?(best, rest, confidence)

    case best do
      %{"source" => "local", "id" => id} when is_integer(id) -> {:link, id, strong?}
      _provider -> {:create, nil, strong?}
    end
  end

  defp strong?(best, rest, confidence) do
    runner_up = rest |> List.first() |> then(&(&1 && &1["score"])) || 0.0

    cond do
      best["score"] == 1.0 -> true
      (confidence || 0.0) >= @strong_match and runner_up <= @weak_runner_up -> true
      true -> false
    end
  end

  # The release name is a fallback, not a peer. Measured across the real
  # library, 96% of releases carry a title in tags and the parser is what the
  # other ~2% rely on — so letting the folder name argue with a provider would
  # make nearly every import ambiguous on its title for no gain.
  defp title_field(best, hints, tags) do
    [candidate(best, "title"), tag_candidate(tags, "book_title")]
    |> scalar(
      required: true,
      equivalence: &title_key/1,
      fallback: release_candidate(hints.title)
    )
  end

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

  defp published_field(best, tags) do
    [candidate(best, "published"), tag_candidate(tags, "published")]
    |> scalar(required: true)
  end

  # Not derivable from the date: year-only knowledge arrives as a literal
  # Jan 1st, and rendering that as a real release day is the exact bug the
  # v1.9.0 punch list fixed for the import forms.
  defp published_format_field(best, tags) do
    [candidate(best, "published_format"), tag_candidate(tags, "published_format")]
    |> scalar(required: false)
    |> default_to("full")
  end

  defp default_to(%Field{value: nil, candidates: []} = field, value) do
    %{field | value: value, source: "default", approved: true}
  end

  defp default_to(field, _value), do: field

  ## recording

  defp recording(level, hints, tags, item) do
    candidates = Map.get(level, "candidates", []) || []

    # **Only a recording we actually believe in gets to fill anything in.**
    # Audible's search widens when a narrow query finds nothing, so a book
    # whose only catalogued edition has a different reader still returns that
    # edition — and taking its publisher, release date and cover would quietly
    # describe this file as a recording it is not. A doubted candidate stays
    # in the list for the operator to pick; it just doesn't get to speak
    # first.
    {doubt, detail, best} = trust(candidates, level, hints)

    %Recording{
      candidates: candidates,
      confidence: Map.get(level, "confidence"),
      query: Map.get(level, "query"),
      query_fields: Map.get(level, "query_fields") || %{},
      doubt: doubt,
      doubt_detail: detail,
      selected_source: best && best["source"],
      selected_id: best && to_string(best["id"]),
      # Which recording this is is a fact with one right answer, so it settles
      # only when we actually know it: a trusted match, or nothing to choose
      # between. A doubted candidate leaves the question open rather than
      # being adopted quietly — that ambiguity was previously invisible,
      # showing up only as fields that mysteriously stayed empty.
      approved: doubt in [:none, :nothing_found]
    }
    |> put_recording_fields(best, tags, item)
  end

  @doc """
  Fills a recording's fields from one catalogue entry, keeping typed values.
  """
  def reseed_recording(%Recording{} = recording, candidate, tags, item) do
    %{
      recording
      | approved: true,
        selected_source: candidate["source"],
        selected_id: to_string(candidate["id"]),
        doubt: :none,
        doubt_detail: nil
    }
    |> put_recording_fields(candidate, tags, item)
  end

  @doc """
  Settles a recording as one no catalogue lists, described by the file alone.
  """
  def reseed_uncatalogued(%Recording{} = recording, tags, item) do
    %{recording | approved: true, selected_source: nil, selected_id: nil}
    |> put_recording_fields(nil, tags, item)
  end

  defp put_recording_fields(%Recording{} = recording, best, tags, item) do
    %{
      recording
      | title: keep_manual(recording.title, scalar([], required: false)),
        published: keep_manual(recording.published, scalar([candidate(best, "published")])),
        publisher:
          keep_manual(
            recording.publisher,
            scalar([candidate(best, "publisher"), tag_candidate(tags, "publisher")])
          ),
        description:
          keep_manual(
            recording.description,
            scalar([candidate(best, "description"), tag_candidate(tags, "description")])
          ),
        cover: keep_manual(recording.cover, cover_field(best, tags, item)),
        narrators: narrator_credits(best, tags)
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
  defp cover_field(best, tags, item) do
    embedded =
      if tags["has_cover_art"] && item.files != [] do
        %Candidate{
          value: List.first(item.files),
          source: "embedded",
          label: "Embedded in the file"
        }
      end

    [candidate(best, "cover_url"), embedded] |> scalar(required: false)
  end

  ## credits

  defp author_credits(best, tags) do
    names = names(best && best["authors"]) || names(tags["authors"]) || []
    source = if names == names(best && best["authors"]), do: source_of(best), else: "tags"

    Enum.map(names, &credit(&1, :author, source))
  end

  defp narrator_credits(best, tags) do
    names = names(best && best["narrators"]) || names(tags["narrators"]) || []
    source = if names == names(best && best["narrators"]), do: source_of(best), else: "tags"

    Enum.map(names, &credit(&1, :narrator, source))
  end

  defp credit(name, kind, source) do
    matches = identity_matches(name, kind)
    people = person_matches(name)

    base = %Credit{name: name, kind: kind, source: source, candidates: matches}

    case {matches, people} do
      # exactly one existing identity by that name — link it and move on
      {[%{exact: true} = match], _people} ->
        %{base | mode: :link, identity_id: match.identity_id, approved: true}

      # nobody by that name at all: create it, backed by one new person.
      # Auto only when a provider-matched work supplied the name — tag names
      # are split by a knowingly imperfect rule.
      {[], []} ->
        %{
          base
          | mode: :create,
            people: Credit.new_person_default(name),
            approved: provider?(source)
        }

      # a Person exists but this identity doesn't — "is this the same human?"
      # is never automated
      {[], _people} ->
        %{base | mode: :create, people: Credit.new_person_default(name), approved: false}

      # more than one identity shares this name; two people really can
      {_several, _people} ->
        %{base | mode: :create, people: Credit.new_person_default(name), approved: false}
    end
  end

  defp identity_matches(name, :author) do
    Author
    |> where([a], fragment("lower(?)", a.name) == ^String.downcase(name))
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
    |> where([n], fragment("lower(?)", n.name) == ^String.downcase(name))
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
    |> where([p], fragment("lower(?)", p.name) == ^String.downcase(name))
    |> Repo.all()
  end

  ## series

  # When linking to an existing book, a proposed series is only offered if the
  # book doesn't already have it: an import may fill a blank, never overwrite
  # curation.
  defp series_links(best, tags, book_id) do
    {proposals, source} =
      case series_proposals(best && best["series"]) do
        [] -> {series_proposals_from_tags(tags), "tags"}
        from_provider -> {from_provider, source_of(best)}
      end

    proposals
    |> Enum.reject(&already_on_book?(&1.name, book_id))
    |> then(fn kept ->
      Enum.map(kept, &series_link(&1.name, &1.number || tag_number(&1.name, tags, kept), source))
    end)
  end

  # The file's series number describes this book's position in the series the
  # file names. Applying it to a series the file did NOT name is inventing a
  # fact — safe only when the file named no series at all and there's exactly
  # one proposal for it to have been about.
  defp tag_number(name, tags, proposals) do
    tagged = presence(tags["series"])

    cond do
      is_nil(tagged) and length(proposals) == 1 -> presence(tags["series_number"])
      tagged && normalize(tagged) == normalize(name) -> presence(tags["series_number"])
      true -> nil
    end
  end

  # Candidates carry series as `%{"name", "number"}`. Older stored matches
  # carry bare strings, and a rescan is not something to require just to read
  # an item, so both shapes are accepted.
  defp series_proposals(nil), do: []

  defp series_proposals(entries) when is_list(entries) do
    entries
    |> Enum.map(&series_proposal/1)
    |> Enum.reject(&is_nil/1)
  end

  defp series_proposals(value) when is_binary(value), do: series_proposals([value])
  defp series_proposals(_other), do: []

  defp series_proposal(%{"name" => name} = entry) when is_binary(name) do
    case presence(name) do
      nil -> nil
      name -> %{name: name, number: presence(entry["number"])}
    end
  end

  defp series_proposal(name) when is_binary(name) do
    case presence(name) do
      nil -> nil
      name -> %{name: name, number: nil}
    end
  end

  defp series_proposal(_other), do: nil

  defp series_proposals_from_tags(tags) do
    case presence(tags["series"]) do
      nil -> []
      name -> [%{name: name, number: presence(tags["series_number"])}]
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

  # `fallback` is a weaker source that only gets a say when the primary ones
  # said nothing — it never argues with them, and never turns a settled field
  # into a choice.
  defp scalar(candidates, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    same? = Keyword.get(opts, :equivalence, &normalize/1)
    candidates = Enum.reject(candidates, &is_nil/1)

    candidates =
      case {groups(candidates, same?), Keyword.get(opts, :fallback)} do
        {[], fallback} when not is_nil(fallback) -> [fallback]
        _primary_had_something -> candidates
      end

    field = %Field{required: required, candidates: candidates}

    case groups(candidates, same?) do
      # nothing proposed it. Optional means waived — an explicit "none", which
      # is what makes "every piece resolved" reachable at all.
      [] ->
        %{field | approved: not required}

      # one answer, whether from one source, several that agree exactly, or
      # several that agree once format labels are set aside
      [group] ->
        value = preferred(group)
        %{field | value: value, source: source_for(candidates, value), approved: true}

      _several ->
        %{field | approved: false}
    end
  end

  # Proposals that mean the same thing, gathered. Every group is one answer;
  # more than one group is a genuine disagreement for the operator to settle.
  defp groups(candidates, same?) do
    candidates
    |> Enum.map(& &1.value)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.group_by(same?)
    |> Map.values()
  end

  # Given two spellings of one answer, the shorter is the title and the longer
  # is the title with a format label bolted on.
  defp preferred(values), do: values |> Enum.uniq() |> Enum.min_by(&String.length/1)

  defp source_for(candidates, value) do
    Enum.find_value(candidates, fn candidate ->
      candidate.value == value && candidate.source
    end)
  end

  defp normalize(string) when is_binary(string) do
    string |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp normalize(other), do: other

  ## candidate helpers

  defp candidate(nil, _key), do: nil

  defp candidate(best, key) do
    case presence(best[key]) do
      nil -> nil
      value -> %Candidate{value: to_string(value), source: source_of(best), label: label_of(best)}
    end
  end

  defp tag_candidate(tags, key) do
    case presence(tags[key]) do
      nil -> nil
      value -> %Candidate{value: to_string(value), source: "tags", label: "The file's tags"}
    end
  end

  defp release_candidate(nil), do: nil

  defp release_candidate(value),
    do: %Candidate{value: value, source: "release_name", label: "The release name"}

  defp source_of(nil), do: nil
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
