defmodule Ambry.Inbox.AutoMatch do
  @moduledoc """
  Proposes what an inbox item is, so confirming it can be one click.

  Three matches, run in order because each answer is the next question: the
  **work** (which Book), the **recording** (which Media), and the **people**
  credited by both. They use different keys and fail independently, so each
  gets its own candidates and its own failure mode.

  Nothing is applied: this writes proposals onto the item, and import is what
  creates records.

  The whole ranked list is stored, so reviewing alternatives costs no provider
  calls. Two providers' records of one book are two descriptions, not rival
  identities, and both may feed the import; a Book already in the library is
  categorically different and lives in its own `"local"` list.
  """

  alias Ambry.Books
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.PersonSearch
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry
  alias Ambry.People
  alias Ambry.Wanted

  require Logger

  @candidate_limit 8

  # How similar a Book has to be before it is worth showing as "you may
  # already have this". Tuned for precision: a miss costs a hand search, and
  # a false offer costs trust in the whole list.
  @offer_local 0.5

  # How many records about the same thing are worth a follow-up call each.
  @group_limit 4

  # Corroboration bonus when two providers independently return the same work.
  @agreement_bonus 0.05

  # What a companion-work marker ("study guide", "graphic novel") costs. Harsh
  # on purpose: these are reliably not the book being imported.
  @companion_factor 0.25

  # Per-word cost for content the query didn't ask for, and the floor it
  # can't push a title below.
  @extra_word_cost 0.08
  @min_length_factor 0.4

  # What counts as the same reader, and what it costs to be a different one.
  @narrator_match 0.85
  @narrator_mismatch 0.5

  # Decisive rather than blended, for the reason in `author_agreement/2`.
  @author_mismatch 0.5

  # What it costs to sit at a different number in the series the label named.
  @series_mismatch 0.5

  @doc """
  Builds work and recording proposals for an item.

  Never raises: a provider being down means fewer candidates, not a failed
  item.
  """
  def match(%InboxItem{} = item, opts \\ []) do
    hints = hints(item)
    {work, recording} = settle_levels(hints, opts)

    %{
      matches: %{
        "work" => work,
        "recording" => recording,
        # Last, because the cast only exists once a record has been found.
        "people" => match_people(work, recording, item.tags || %{}, opts),
        "hints" => stringify_hints(hints)
      }
    }
  end

  # Matching is a loop, not a pipeline: a round's records can hold a better
  # query than the one that found them. The gate is corroboration, not
  # similarity — gating on the score is circular, since scoring low is what a
  # shelf label causes. Two providers landing on one answer is evidence the
  # scorer cannot see; one provider's top hit is not.
  @max_rounds 3

  # Refinement only runs for a work still under Seed's adoption bar: a
  # confident round 1 has nothing to fix.
  @refine_below 0.65

  defp settle_levels(hints, opts) do
    work = match_work(hints, opts)

    # A work's own edition list is a third key alongside searching, and the
    # most direct route to recordings no storefront will return.
    recording = match_recording(hints, work, opts)

    refine({work, recording}, hints, MapSet.new([consensus_key(hints.title)]), 1, opts)
  end

  defp refine({work, recording} = settled, hints, seen, round, opts) do
    with true <- round < @max_rounds,
         true <- (work["confidence"] || 0.0) < @refine_below,
         %{} = refined <- consensus_hints(work, recording, hints),
         false <- MapSet.member?(seen, consensus_key(refined.title)) do
      work2 = match_work(refined, opts)
      recording2 = match_recording(refined, work2, opts)
      merged = {merge_level(work, work2, refined), merge_level(recording, recording2, refined)}

      refine(merged, refined, MapSet.put(seen, consensus_key(refined.title)), round + 1, opts)
    else
      _settled_or_no_consensus -> settled
    end
  end

  # Grouped across both levels and narrator-blind: two different recordings
  # of one work still corroborate the work.
  defp consensus_hints(work, recording, hints) do
    current = consensus_key(hints.title)

    ((work["candidates"] || []) ++ (recording["candidates"] || []))
    |> Enum.reduce([], fn candidate, groups ->
      case Enum.find_index(groups, fn [held | _rest] -> works_agree?(held, candidate) end) do
        nil -> groups ++ [[candidate]]
        index -> List.update_at(groups, index, &(&1 ++ [candidate]))
      end
    end)
    |> Enum.map(fn group ->
      {group, group |> Enum.map(& &1["source"]) |> Enum.uniq() |> length()}
    end)
    |> Enum.filter(fn {[held | _rest], sources} ->
      sources >= 2 and consensus_key(held["title"]) != nil
    end)
    |> Enum.sort_by(fn {group, sources} -> {-sources, -best_score(group)} end)
    |> case do
      [] ->
        nil

      # The strongest corroborated answer decides, and only a disagreeing
      # one refines: agreement with the question ends the loop.
      [{[held | _rest] = group, _sources} | _rest_groups] ->
        if consensus_key(held["title"]) != current do
          best = Enum.min_by(group, &String.length(&1["title"] || ""))

          %{
            hints
            | title: strip_ordinal(best["title"]),
              author: List.first(best["authors"] || []) || hints.author
          }
        end
    end
  end

  defp works_agree?(one, other) do
    consensus_key(one["title"]) == consensus_key(other["title"]) and
      compatible?(one["authors"], other["authors"])
  end

  # ", Book 1" stripped so Audible's "…Sorcerer's Stone, Book 1" and the
  # editions' bare title count as one answer.
  defp consensus_key(nil), do: nil
  defp consensus_key(title), do: title |> strip_ordinal() |> title_key() |> presence()

  defp strip_ordinal(title),
    do: String.replace(title || "", ~r/,?\s+(?:book|bk\.?|vol\.?|volume)\s+\d+\s*$/i, "")

  defp best_score(group), do: group |> Enum.map(&(&1["score"] || 0.0)) |> Enum.max()

  # Rounds add evidence, never remove it: records merge add-only under their
  # stable refs. The level's description follows the latest round.
  defp merge_level(old, new, hints) do
    candidates = add_records(old["candidates"] || [], new["candidates"] || [])

    new
    |> Map.put("candidates", candidates)
    |> Map.put("local", add_records(old["local"] || [], new["local"] || []))
    |> Map.put("providers", merge_outcomes(old["providers"] || [], new["providers"] || []))
    |> Map.put("confidence", confidence(candidates, hints.author))
  end

  # Identity is the ref, but the score is derived: a record re-found by a
  # better query keeps the better score, or the refinement changes nothing.
  defp add_records(existing, found) do
    found
    |> Enum.reduce(existing, fn record, acc ->
      case Enum.find_index(acc, &(ref(&1) == ref(record))) do
        nil -> acc ++ [record]
        index -> List.update_at(acc, index, &merge_record(&1, record))
      end
    end)
    |> Enum.sort_by(&(&1["score"] || 0.0), :desc)
  end

  defp merge_record(old, new) do
    Map.merge(old, new, fn
      "score", held, fresh -> max(held || 0.0, fresh || 0.0)
      _key, held, fresh -> fresh || held
    end)
  end

  defp merge_outcomes(existing, fresh) do
    fresh_ids = MapSet.new(fresh, & &1["id"])
    Enum.reject(existing, &MapSet.member?(fresh_ids, &1["id"])) ++ fresh
  end

  @doc """
  Everything known about each human this import will credit.

  Keyed by `person_key/1`, one entry per distinct human.

  A person already in the library is never searched, which is what makes this
  affordable across a recurring full-cast series. The check is an exact name
  match, because skipping the search produces a silence rather than a
  candidate the operator can reject.

  Records are evidence, never decisions.
  """
  def match_people(work, recording, tags, opts \\ []) do
    work
    |> credited_people(recording, tags)
    |> Map.new(fn {name, roles} -> {person_key(name), person_result(name, roles, opts)} end)
  end

  @doc """
  How a human is referred to across the matches and the draft.

  Punctuation-insensitive: the databases disagree about dots and spaces, and
  none of those spellings is a different human.

  `Draft.PersonDecision` keys are these strings, so the key IS the sameness
  rule for humans.
  """
  # Letters and digits alone: spacing has to go too, or "TJ Klune" and
  # "T.J. Klune" stay apart. Accents fold as well.
  def person_key(name) when is_binary(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
  end

  @doc """
  `person_key/1` as an Ecto fragment, for asking the question in SQL.

  Beside its Elixir twin because the two have to agree.

      where([a], person_key_sql(a.name) == ^AutoMatch.person_key(name))
  """
  defmacro person_key_sql(field) do
    quote do
      fragment("regexp_replace(lower(unaccent(?)), '[^[:alnum:]]+', '', 'g')", unquote(field))
    end
  end

  # Filler words a series name wears in one source and not another.
  @series_filler ~w(trilogy series saga duology quartet quintet cycle sequence collection books novels)

  @doc """
  Whether two spellings name one series.

  Filler words (Trilogy, Saga, Series), punctuation, accents and articles
  fold, and a subtitle head counts the way it does for titles: "Kushiel's
  Legacy: Phedre Trilogy" is "Kushiel's Legacy".
  """
  def same_series?(one, other) when is_binary(one) and is_binary(other) do
    a = series_key(one)
    b = series_key(other)

    a == b or series_key(series_head(one)) == b or series_key(series_head(other)) == a
  end

  def same_series?(_one, _other), do: false

  defp series_head(name), do: name |> String.split(~r/\s*:\s/u, parts: 2) |> hd()

  defp series_key(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 in ["the", "a", "an"] or &1 in @series_filler))
    |> Enum.join(" ")
  end

  @doc """
  The photo and biography to propose for one credited human.

  The proposal laid on top of the evidence, under two rules:

    * **Only a candidate whose name is actually the credited name.** Provider
      person-search is recall-first, which is right for a grid a human reads
      and wrong for an automatic choice.
    * **First provider with something usable wins**, in the operator's
      priority order. Photo and biography are chosen independently.

  An exact name is still not an identity, which is why this proposes rather
  than settles.
  """
  def person_proposal(nil), do: %{}

  def person_proposal(person) do
    named =
      person
      |> Map.get("candidates", [])
      |> Enum.filter(&same_human?(&1["name"], person["name"]))

    %{}
    |> put_proposal(:image_url, :image_source, pick(named, &first(&1["images"])))
    |> put_proposal(
      :description,
      :description_source,
      pick(named, &usable_bio(&1["description"]))
    )
  end

  # The first candidate that has one, carrying its provider: provenance is
  # written from this, so the value and its source have to travel together.
  defp pick(candidates, take) do
    Enum.find_value(candidates, fn candidate ->
      case take.(candidate) do
        nil -> nil
        value -> {value, candidate["source"]}
      end
    end)
  end

  defp put_proposal(map, _value_key, _source_key, nil), do: map

  defp put_proposal(map, value_key, source_key, {value, source}),
    do: map |> Map.put(value_key, value) |> Map.put(source_key, source)

  defp same_human?(one, other) when is_binary(one) and is_binary(other),
    do: person_key(one) == person_key(other)

  defp same_human?(_one, _other), do: false

  # Providers return these where they have no biography. Storing one as
  # somebody's life story is worse than blank: blank is visibly unfinished.
  @nonsense_bios ["n/a", "na", "none", "unknown", "no description", "-", "."]

  defp usable_bio(text) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed != "" and String.downcase(trimmed) not in @nonsense_bios, do: trimmed
  end

  defp usable_bio(_other), do: nil

  defp person_result(name, roles, opts) do
    case People.people_named(name) do
      # Already ours, so nothing is searched.
      [_first | _rest] = people ->
        %{
          "name" => name,
          "roles" => roles,
          "local" => Enum.map(people, &local_person/1),
          "candidates" => [],
          "providers" => []
        }

      [] ->
        {candidates, outcomes} = search_person(name, opts)

        %{
          "name" => name,
          "roles" => roles,
          "local" => [],
          "candidates" => candidates,
          "providers" => outcomes
        }
    end
  end

  @doc """
  The people the library already has by this name.

  Kept away from the provider candidates: a provider record is evidence about
  a human, while one of these is a human.
  """
  def local_people(name), do: name |> People.people_named() |> Enum.map(&local_person/1)

  defp local_person(person) do
    %{
      "source" => "local",
      "id" => person.id,
      "name" => person.name,
      "has_image" => is_binary(person.image_path),
      "has_description" => not is_nil(presence(person.description))
    }
  end

  defp search_person(name, opts) do
    {candidates, outcomes} =
      Enum.reduce(PersonSearch.providers(), {[], []}, fn entry, {candidates, outcomes} ->
        {matches, provider_outcomes} = PersonSearch.matches_with_outcome(entry, name, opts)

        {candidates ++ Enum.map(matches, &person_candidate(&1, name)),
         outcomes ++ provider_outcomes}
      end)

    {rank_people(candidates, name), outcomes}
  end

  @doc """
  One provider's answer about a human, scored against the name we asked for.

  Shared with `Ambry.Inbox.Lookup`, so a re-search builds the same records.
  """
  def person_candidate(%PersonSearch.Match{} = match, asked_for) do
    %{
      "source" => "provider:#{match.provider_id}",
      "provider_name" => match.provider_name,
      "id" => to_string(match.id),
      "name" => match.name,
      "description" => presence(match.description),
      # what tells two same-named humans apart in a grid
      "note" => presence(match.note),
      "images" => match.images,
      "score" => person_score(match.name, asked_for)
    }
  end

  @doc """
  How well a returned name answers the name we asked about.

  **Not a string distance.** Jaro scores "Ty Franck" against "Tyler Corey
  Franck" lower than against an unrelated name sharing letters, so the
  ordering is by what the names structurally share, as in
  `author_agreement/2`:

    * `1.0` — the same name once accents and punctuation are folded away
      (`person_key/1`), so "Émile Zola" and "Emile Zola" are one person
    * `0.8` — one name's words are all inside the other's: "Ty Franck" within
      "Tyler Corey Franck", the pen-name-and-full-name case
    * `0.6` — they share a word, which is the floor `PersonSearch` already
      filters at
    * `0.0` — nothing shared, which a filtered search shouldn't return

  Ties break on usefulness: a candidate carrying a photo and a biography is
  more likely to be the documented human.
  """
  def person_score(name, asked_for) do
    wanted = name_tokens(asked_for)
    got = name_tokens(name)

    cond do
      person_key(name || "") == person_key(asked_for || "") -> 1.0
      Enum.empty?(wanted) or Enum.empty?(got) -> 0.0
      covered?(wanted, got) or covered?(got, wanted) -> 0.8
      Enum.any?(wanted, fn word -> Enum.any?(got, &same_word?(&1, word)) end) -> 0.6
      true -> 0.0
    end
  end

  # Every word on one side answered by a word on the other.
  defp covered?(words, others),
    do: Enum.all?(words, fn word -> Enum.any?(others, &same_word?(&1, word)) end)

  # A shortening is the same word: "Ty" for Tyler. Words under two characters
  # are dropped already, so initials cannot collapse onto everything.
  defp same_word?(word, other),
    do: String.starts_with?(word, other) or String.starts_with?(other, word)

  @doc """
  People, best answer first.

  Every candidate is re-scored against the name being asked about now, not
  only the new arrivals: a re-search changes the question. Nothing is dropped;
  a record that stops answering sinks.
  """
  def rank_people(candidates, asked_for) do
    candidates
    |> Enum.map(&Map.put(&1, "score", person_score(&1["name"], asked_for)))
    |> Enum.sort_by(&{&1["score"] || 0.0, person_substance(&1)}, :desc)
  end

  # A face and a biography, as a tie-break between equally-named candidates.
  defp person_substance(candidate) do
    has_image = if candidate["images"] in [nil, []], do: 0, else: 1
    has_bio = if presence(candidate["description"]), do: 1, else: 0
    has_image + has_bio
  end

  # The union of what the records name and what the tags name, never `Seed`'s
  # records-else-tags fallback: a doubted recording credits the tags' narrator
  # while the top record names somebody else. Over-searching costs one cached
  # call; under-searching costs the import its faces.
  defp credited_people(work, recording, tags) do
    authors = names(work, "authors") ++ tag_names(tags, "authors")

    narrators =
      (names(recording, "narrators") ++ tag_names(tags, "narrators"))
      |> Enum.reject(&placeholder_narrator?/1)

    merge_roles(Enum.map(authors, &{&1, "author"}) ++ Enum.map(narrators, &{&1, "narrator"}))
  end

  defp names(level, key) do
    level
    |> Map.get("candidates", [])
    |> top_group()
    |> Enum.flat_map(&(&1 |> Map.get(key) |> stated_names()))
  end

  defp tag_names(tags, key), do: tags |> Map.get(key) |> stated_names()

  defp stated_names(value) do
    value
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp merge_roles(pairs) do
    Enum.reduce(pairs, [], fn {name, role}, acc ->
      key = person_key(name)

      case Enum.find_index(acc, fn {held, _roles} -> person_key(held) == key end) do
        nil ->
          acc ++ [{name, [role]}]

        index ->
          List.update_at(acc, index, fn {held, roles} -> {held, Enum.uniq(roles ++ [role])} end)
      end
    end)
  end

  @doc """
  The records that look like they're about the same thing as the best one.

  Used for scoring, for deciding what to pre-tick, and for deciding which
  records earn a details call. Never for merging.
  """
  def top_group([]), do: []

  def top_group(candidates) do
    # `Enum.max_by`, not `hd/1`: the head is only the best of an already-ranked
    # list, and callers hand over provider-ordered ones.
    best = Enum.max_by(candidates, &(&1["score"] || 0.0))

    candidates
    |> Enum.filter(&agrees?(&1, best))
    |> Enum.take(@group_limit)
  end

  @doc """
  The records worth *pre-ticking* — narrower than `top_group/1` once the file
  has said who read it.

  Ticking a record says "this describes my file", which a record naming no
  narrator cannot support. It stays in the group for every other purpose, but
  a silent record is unpenalised, so it would otherwise stay at 1.000, get
  ticked, and hand the recording somebody else's date.

  Only bites when some record IS corroborated; otherwise this is
  `top_group/1`.
  """
  def settled_group(records) do
    group = top_group(records)

    case Enum.filter(group, &(&1["narrator_evidence"] == "supported")) do
      [] -> group
      corroborated -> corroborated
    end
  end

  @doc """
  Whether a narrator value names nobody in particular.

  "Full Cast" is a label for a cast, not a person, and taken literally it
  manufactures a narrator conflict on every dramatized edition.

  A placeholder is "didn't say", not "said something different", so it neither
  argues with the catalogue nor becomes a Person.
  """
  def placeholder_narrator?(name) when is_binary(name) do
    normalize(name) in [
      "full cast",
      "full cast recording",
      "a full cast",
      "cast",
      "cast recording",
      "multi cast",
      "multicast",
      "multi-cast",
      "dramatized",
      "dramatised",
      "various",
      "various narrators",
      "various artists",
      "multiple narrators",
      "multiple",
      "uncredited",
      "unknown",
      "n/a"
    ]
  end

  def placeholder_narrator?(_other), do: false

  @doc """
  What we think the item is, from its tags first and its release name second.

  Tags win because they are far more reliable: roughly 96% of ordinary
  releases carry a title and author in tags, against 55% whose name yields an
  author.
  """
  def hints(%InboxItem{} = item) do
    tags = item.tags || %{}
    parsed = ReleaseName.parse(item.path)
    tag_parsed = ReleaseName.parse(tags["book_title"] || "")
    part = part_hint(parsed, tag_parsed)

    %{
      # Stripped of release junk before it becomes a query: "(Unabridged)"
      # searches worse and still returns something, so the zero-result retry
      # never rescues it.
      title: ReleaseName.strip_noise(tags["book_title"]) || parsed.title,
      author: first(tags["authors"]) || parsed.author,
      narrator: stated_narrator(tags["narrators"]) || parsed.narrator,
      series: presence(tags["series"]) || parsed.series,
      # A series and a number together are an identity
      # (`series_identity/2`), and the only thing stopping a label-tagged
      # later volume matching book one.
      series_number:
        suppress_part_polluted_series_number(
          presence_number(tags["series_number"]) ||
            tag_parsed.series_number ||
            parsed.series_number,
          part,
          presence(tags["series"]) || parsed.series
        ),
      # "Part 1 of 2", from the file name first (release names are precise
      # about this where tag titles are messy) and the tag title's tail second.
      part_number: part && elem(part, 0),
      parts_total: part && elem(part, 1),
      asin: presence(tags["asin"]) || parsed.asin,
      # Beside `title` rather than folded into it: the two disagree on more
      # than half of an ordinary library's releases and neither reliably wins.
      release_title: parsed.title,
      # Everything the item says about itself, unparsed, for checking a
      # candidate back against: a name stating its narrator in a shape no
      # field captures leaves `narrator` nil and the scorer a no-op.
      raw: raw_text(item)
    }
  end

  # Basenames only: parent directories are filesystem layout, not evidence.
  defp raw_text(%InboxItem{} = item) do
    [Path.basename(item.path || "")]
    |> Enum.concat(Enum.map(InboxItem.included(item), &Path.basename/1))
    |> Enum.concat(tag_text(item.tags))
    |> Enum.join(" ")
  end

  defp tag_text(tags) when is_map(tags) do
    tags |> Map.values() |> List.flatten() |> Enum.filter(&is_binary/1)
  end

  defp tag_text(_tags), do: []

  # Local Books go in their own list: reusing a Book you have is an outcome,
  # and a provider record is evidence.
  defp match_work(hints, opts) do
    {query, candidates, outcomes} = search_ladder(:work, work_queries(hints), hints, opts)

    query
    |> level_result(candidates, outcomes, hints.author)
    |> Map.put("local", local_books(hints))
    |> hydrate_top(opts)
  end

  # The work level asks the same two questions the recording level does,
  # minus the ASIN — that is a recording key and names an edition, not a work.
  defp work_queries(hints) do
    tagged = work_query(hints)

    [tagged, release_title_query(hints, tagged)] |> Enum.reject(&is_nil/1)
  end

  # Every record about the top work, since they all feed the field
  # candidates. Records about other works stay thin until ticked.
  defp hydrate_top(%{"candidates" => candidates} = result, opts) do
    wanted = candidates |> top_group() |> MapSet.new(&ref/1)

    {hydrated, failures} =
      Enum.map_reduce(candidates, [], fn record, failures ->
        if MapSet.member?(wanted, ref(record)) do
          case details_with_outcome(record, opts) do
            {record, nil} -> {record, failures}
            {record, outcome} -> {record, failures ++ [outcome]}
          end
        else
          {record, failures}
        end
      end)

    result
    |> Map.put("candidates", hydrated)
    # One chip per provider however many of its records were hydrated.
    |> Map.put("providers", merge_outcomes(result["providers"] || [], tally(failures)))
  end

  defp hydrate_top(result, _opts), do: result

  @doc "How a record is referred to: its provider and that provider's id."
  def ref(record), do: {record["source"], to_string(record["id"])}

  @doc """
  Marks a record as having had its full details fetched.

  Records about the top work are hydrated while matching; the rest stay thin
  until the operator ticks one.
  """
  def hydrated(record), do: Map.put(record, "hydrated", true)

  @doc """
  Everything a provider knows about one record, for filling in a thin search
  hit: a search result is a summary, often missing the edition list, the full
  description and the cover.
  """
  def details(record, opts \\ []) do
    {record, _outcome} = details_with_outcome(record, opts)
    record
  end

  @doc """
  The same fetch, plus a failed outcome when the provider couldn't be reached.

  A thin record and an unfetched record are not the same thing. Keeping the
  summary is right, but doing it quietly costs the record its description,
  cover and edition list with nothing saying so.

  The outcome is what makes it visible and what makes it come back: `RunMatch`
  fails a job with any unreached provider, and provider errors are never
  cached.
  """
  def details_with_outcome(record, opts \\ []) do
    case details_for(record, opts) do
      # Nothing to report and nothing a retry could do.
      :no_provider ->
        {record, nil}

      {:ok, entry, fuller} ->
        # Success is reported too: outcomes replace each other by id, so
        # "couldn't be reached" would outlive the retry that fixed it.
        {record |> Map.merge(fuller) |> hydrated(), Outcome.ok(entry, 1, :details)}

      # nil when the provider was never asked. Callers drop it.
      {:error, entry, reason} ->
        {record, Outcome.from_error(entry, reason, :details)}
    end
  end

  defp details_for(%{"source" => "provider:" <> provider_id, "id" => id}, opts)
       when is_binary(id) do
    case Registry.fetch(provider_id) do
      {:ok, entry} -> details_from(entry, id, opts)
      {:error, _unknown} -> :no_provider
    end
  end

  defp details_for(_record, _opts), do: :no_provider

  defp details_from(entry, id, opts) do
    case Providers.book_details(entry.id, id, opts) do
      {:ok, book} ->
        # Only fields the summary can be missing: re-deriving the title,
        # authors or score would move what the operator already saw ranked.
        fuller =
          %{
            "description" => presence(book.description),
            "cover_url" => presence(book.cover_url),
            "publisher" => presence(book.publisher),
            "series" => series_refs(book.series)
          }
          |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
          |> Map.new()

        {:ok, entry, fuller}

      {:error, reason} ->
        Logger.warning(fn ->
          "Auto-match: details for #{entry.id}/#{id}: #{inspect(reason)}"
        end)

        {:error, entry, reason}
    end
  end

  defp match_recording(hints, work, opts) do
    {query, candidates, outcomes} =
      search_ladder(:recording, recording_queries(hints), hints, opts)

    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints, opts)

    level_result(
      query,
      candidates
      |> Kernel.++(editions)
      |> dedupe_records()
      |> apply_narrator_evidence(hints)
      |> mark_wanted(),
      outcomes ++ edition_outcomes,
      hints.author
    )
  end

  @doc """
  Marks the candidates the operator is already waiting for.

  It does not move the score: a watch is evidence about intent, not about the
  file. It orders equals and labels them.
  """
  def mark_wanted(candidates), do: mark_wanted(candidates, Wanted.open_refs())

  @doc false
  def mark_wanted(candidates, wanted_refs) do
    if Enum.empty?(wanted_refs) do
      candidates
    else
      Enum.map(candidates, fn record ->
        if MapSet.member?(wanted_refs, ref(record)) do
          Map.put(record, "wanted", true)
        else
          record
        end
      end)
    end
  end

  # An ASIN leads when there is one, but never replaces the title search: one
  # that doesn't resolve would end the level at zero candidates.
  defp recording_queries(hints) do
    # Structured, not concatenated: a storefront matches `title` against the
    # title alone. The narrator tells two recordings of one work apart.
    tagged = %Provider.Query{title: hints.title, author: hints.author, narrator: hints.narrator}

    [
      hints.asin && %Provider.Query{keywords: hints.asin},
      tagged,
      release_title_query(hints, tagged)
    ]
    |> Enum.reject(&is_nil/1)
  end

  # The release name as a second question, asked only when the tag title's
  # came back empty: a genuinely different source, not a better one. Whatever
  # comes back is ranked against the file's raw text, so bad answers rank out.
  defp release_title_query(%{release_title: release} = hints, template) when is_binary(release) do
    cond do
      same_question?(release, hints.title) -> nil
      # A name that parsed to nothing but the author is not a second opinion
      # about the title: searching an author's name finds their other books.
      same_question?(release, hints.author) -> nil
      true -> %{template | title: release, keywords: nil}
    end
  end

  defp release_title_query(_hints, _template), do: nil

  # Two sources spelling one title differently is not a second opinion.
  defp same_question?(one, two) when is_binary(one) and is_binary(two),
    do: comparable(one) == comparable(two)

  defp same_question?(_one, _two), do: false

  defp comparable(text), do: text |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, "")

  # Asks each query in turn, stopping at the first that finds anything: a
  # level that finds nothing is usually a polluted question.
  #
  # Every attempt's outcomes are tallied, not just the winner's, or a provider
  # rate-limited on the first question looks like it answered.
  defp search_ladder(level, queries, hints, opts, outcomes \\ [])

  defp search_ladder(_level, [], _hints, _opts, outcomes), do: {nil, [], tally(outcomes)}

  defp search_ladder(level, [query | rest], hints, opts, outcomes) do
    {candidates, fresh} = provider_books(level, query, hints, opts)
    outcomes = outcomes ++ fresh

    if candidates == [] and rest != [] do
      search_ladder(level, rest, hints, opts, outcomes)
    else
      {query, candidates, tally(outcomes)}
    end
  end

  @doc """
  Collapses records **one provider** returned more than once.

  Never two *different* providers' records, which are two descriptions of one
  book and stay separate rows. This is one database returning the same edition
  several times, crowding alternatives off a list capped at
  #{@candidate_limit}.

    * **Merge, don't drop**: the duplicates are not identical, so the survivor
      takes the union.
    * **First occurrence keeps the identity**, since the draft points at
      records by `{source, id}`. Anything the operator ticked is pinned.

  Strict about what counts as the same record: same provider, same normalized
  title, the same narrators, and no disagreement on ASIN or publisher. Two
  ASINs for one recording are regional editions, not duplicates.
  """
  def dedupe_records(records, pinned \\ MapSet.new()) do
    Enum.reduce(records, [], fn record, kept ->
      case duplicate_index(kept, record, pinned) do
        nil -> kept ++ [record]
        index -> List.update_at(kept, index, &absorb(&1, record))
      end
    end)
  end

  defp duplicate_index(kept, record, pinned) do
    if !MapSet.member?(pinned, ref(record)) do
      Enum.find_index(kept, &duplicate?(&1, record))
    end
  end

  defp duplicate?(kept, record) do
    kept["source"] == record["source"] and
      normalize(kept["title"] || "") == normalize(record["title"] || "") and
      narrator_key(kept) == narrator_key(record) and
      agreeable?(kept["asin"], record["asin"]) and
      agreeable?(kept["publisher"], record["publisher"])
  end

  defp narrator_key(record) do
    record["narrators"] |> List.wrap() |> Enum.map(&normalize/1) |> Enum.sort()
  end

  defp agreeable?(nil, _other), do: true
  defp agreeable?(_value, nil), do: true
  defp agreeable?(value, other), do: value == other

  # The survivor keeps what it had and gains what it lacked. The count rides
  # along so a provider's duplication stays visible rather than tidied away.
  defp absorb(kept, record) do
    record
    |> Map.merge(kept, fn _key, incoming, held ->
      if held in [nil, "", []], do: incoming, else: held
    end)
    |> Map.put("duplicates", (kept["duplicates"] || 1) + 1)
  end

  @doc """
  Re-scores recordings by what the file *says*, not by what the parser could
  get out of it.

  Everything else here runs forwards: read the item, build a query, score
  what comes back. This runs **backwards**, looking for each candidate's
  narrators in the item's raw text, because `hints.narrator` is nil whenever
  the parser found no credit and a recording by the wrong reader then keeps a
  perfect score.

  Three-valued, and the middle value is the one that matters:

    * **supported** — a candidate's reader is named in the file. Corroboration.
    * **unstated** — *no* candidate's reader is named anywhere, which is the
      ordinary case, so nothing is adjusted.
    * **contradicted** — this candidate's reader is absent *while a rival's is
      present*. Only then has the file spoken: it named a reader, just not
      through any field we parse, and it isn't this one.

  Candidates carrying no narrator are never touched, and this only fires when
  `hints.narrator` is nil, so exactly one narrator mechanism is ever active.
  """
  def apply_narrator_evidence(candidates, hints)

  def apply_narrator_evidence(candidates, %{narrator: narrator, raw: raw})
      when is_binary(raw) and is_nil(narrator) do
    haystack = tokens(raw)
    supported = Map.new(candidates, &{ref(&1), named_in?(&1["narrators"], haystack)})

    if Enum.any?(supported, fn {_ref, yes?} -> yes? end) do
      candidates |> Enum.map(&verdict(&1, supported[ref(&1)])) |> order_candidates()
    else
      candidates
    end
  end

  def apply_narrator_evidence(candidates, _hints), do: candidates

  # A record with no narrators is silent, not wrong.
  defp verdict(%{"narrators" => narrators} = record, _supported?) when narrators in [nil, []],
    do: record

  defp verdict(record, supported?) do
    # From the untouched base, never multiplied into the running score: a
    # re-search would otherwise sink a candidate further on every visit.
    base = record["base_score"] || record["score"] || 0.0
    factor = if supported?, do: 1.05, else: @narrator_mismatch

    record
    |> Map.put("base_score", base)
    |> Map.put("score", base |> Kernel.*(factor) |> min(1.0) |> Float.round(3))
    |> Map.put("narrator_evidence", if(supported?, do: "supported", else: "contradicted"))
  end

  # Any one reader is enough: a full-cast release names a handful of its
  # fifteen actors at most, and one of them appearing IS the corroboration.
  defp named_in?(narrators, haystack) do
    Enum.any?(List.wrap(narrators), fn name ->
      tokens(name)
      |> MapSet.to_list()
      |> Enum.filter(&(String.length(&1) >= 3))
      |> case do
        # Initials and mononyms carry too little to search for, so a name
        # reduced to nothing abstains rather than guessing.
        [] -> false
        parts -> Enum.all?(parts, &MapSet.member?(haystack, &1))
      end
    end)
  end

  defp tokens(nil), do: MapSet.new()

  defp tokens(string) do
    string
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> MapSet.new()
  end

  @doc """
  The recordings the given work records are known to have.

  This is what finds an edition a storefront has erased: when rights lapse a
  title vanishes from search and ASIN lookup alike, while a database of
  editions keeps it.

  Every capable record is asked, never only the first. A provider whose
  edition list carries no narrator is silent at this level.
  """
  def editions_for(records, hints, opts \\ []) do
    {candidates, outcomes} =
      records
      |> Enum.filter(&editions_capable?/1)
      |> Enum.reduce({[], []}, fn record, {candidates, outcomes} ->
        "provider:" <> provider_id = record["source"]

        {found, outcome} =
          fetch_editions(provider_id, record["id"], hints, work_ref(record), opts)

        {candidates ++ found, outcomes ++ outcome}
      end)

    {candidates, tally(outcomes)}
  end

  @doc """
  Collapses many calls to one provider into the one chip the operator reads.

  Outcomes de-duplicate by id downstream and the last wins, so a failure
  outranks an answer: otherwise a provider rate-limited on one of four calls
  reports a clean `ok`.
  """
  def tally_outcomes(outcomes), do: tally(outcomes)

  defp tally(outcomes) do
    outcomes
    |> Enum.group_by(& &1["id"])
    |> Enum.map(fn {_id, [first | _rest] = group} ->
      # Summed, so a partial answer reports what did come back.
      count = Enum.sum_by(group, &(&1["count"] || 0))

      case Enum.find(group, &Outcome.failed?/1) do
        nil -> %{first | "status" => "ok", "count" => count}
        failure -> %{failure | "count" => count}
      end
    end)
  end

  defp editions_capable?(%{"source" => "provider:" <> provider_id, "id" => id})
       when is_binary(id) do
    case Registry.fetch(provider_id) do
      {:ok, entry} -> :editions in entry.capabilities
      _unknown -> false
    end
  end

  defp editions_capable?(_record), do: false

  # An edition from a work's own list carries that work with it, so ticking
  # the recording settles the book too.
  defp work_ref(%{"source" => source, "id" => id}), do: %{"source" => source, "id" => id}

  defp fetch_editions(provider_id, work_id, hints, of_work, opts) do
    case Providers.editions(provider_id, work_id, opts) do
      {:ok, books} ->
        {:ok, entry} = Registry.fetch(provider_id)

        candidates =
          Enum.map(
            books,
            &(&1 |> provider_candidate(entry, hints) |> Map.put("of_work", of_work))
          )

        {candidates, [Outcome.ok(entry, length(candidates), :editions)]}

      {:error, reason} ->
        Logger.warning(fn -> "Auto-match: editions for #{provider_id}: #{inspect(reason)}" end)

        # An id the registry has never heard of cannot be named or retried.
        case Registry.fetch(provider_id) do
          {:ok, entry} -> {[], List.wrap(Outcome.from_error(entry, reason, :editions))}
          {:error, _unknown} -> {[], []}
        end
    end
  end

  defp work_query(%{title: nil}), do: nil

  defp work_query(hints), do: %Provider.Query{title: hints.title, author: hints.author}

  defp level_result(query, candidates, outcomes, author) do
    %{
      "query" => query && to_string(query),
      # The flattened string is what the cache keys on; the fields are what
      # was actually asked, and what the operator reads when a match is wrong.
      "query_fields" => query_fields(query),
      "candidates" => rank(candidates),
      "confidence" => confidence(candidates, author),
      # Without this a provider that fails vanishes silently.
      "providers" => outcomes
    }
  end

  @doc """
  Orders records best-first and caps the list.

  Records are not fused when two providers return the same thing: collapsing
  them deletes the loser's payload and makes the list read as rival
  identities.
  """
  def rank(candidates) do
    candidates |> order_candidates() |> Enum.take(@candidate_limit)
  end

  @doc """
  Best first: by score, and among equal scores by what the file corroborated.

  The boost is capped at 1.0, so a corroborated recording and a silent one
  can tie there; ordering decides which of two equals the file spoke about.
  """
  def order_candidates(candidates) do
    Enum.sort_by(candidates, &{&1["score"] || 0.0, wanted(&1), corroboration(&1)}, :desc)
  end

  # Ahead of corroboration among equals; neither outranks a better score.
  defp wanted(%{"wanted" => true}), do: 1
  defp wanted(_record), do: 0

  defp corroboration(%{"narrator_evidence" => "supported"}), do: 2
  defp corroboration(%{"narrator_evidence" => "contradicted"}), do: 0
  defp corroboration(_record), do: 1

  defp query_fields(nil), do: %{}

  defp query_fields(%Provider.Query{} = query) do
    %{
      "title" => presence(query.title),
      "author" => presence(query.author),
      "narrator" => presence(query.narrator),
      "keywords" => presence(query.keywords)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc """
  Whether two records describe the same thing.

  **Everything they both say has to agree; a field one of them doesn't carry
  is not a disagreement.** A binary predicate rather than a key, because
  "didn't say" is compatible with every answer and no key can express that.

  The ASIN is not part of it: a storefront's and a database's record of one
  reading routinely differ by a regional variant, so an ASIN may confirm a
  match (`score/5`'s job) but never deny one.

  Callers pass one level's candidates at a time: at the work level the authors
  decide, at the recording level the narrators do.
  """
  def agrees?(one, other) do
    same_stated_title?(one["title"] || "", other["title"] || "") and
      companion?(one["title"]) == companion?(other["title"]) and
      compatible?(one["narrators"], other["narrators"]) and
      compatible?(one["authors"], other["authors"])
  end

  # A companion work agrees with its subject on every other test, since it
  # credits nobody and all three read "didn't say". Without this the record
  # with the worst data earns the most trust.
  defp companion?(title), do: companion_penalty(title || "") != 1.0

  # A title and that same title carrying its subtitle are one answer written
  # two ways. Asymmetric containment, not a shared prefix: one title has to be
  # the WHOLE of the other's head. Compared as `title_key/1`, so a leading
  # article is not a rival spelling.
  defp same_stated_title?(one, other) do
    a = title_key(one)
    b = title_key(other)

    a == b or title_key(title_head(one)) == b or title_key(title_head(other)) == a
  end

  # Naming fewer of the same people is compatible with naming more: "said
  # less" corroborates, "said different" does not.
  defp compatible?(one, other) do
    case {name_set(one), name_set(other)} do
      {[], _unstated} -> true
      {_unstated, []} -> true
      {one, other} -> MapSet.subset?(one, other) or MapSet.subset?(other, one)
    end
  end

  defp name_set(names) do
    case List.wrap(names) do
      [] -> []
      names -> MapSet.new(names, &person_key/1)
    end
  end

  # Confidence is about the decision, not the top hit: a strong match with a
  # genuinely different runner-up is what a human should look at. But
  # corroboration is not a rival, or the best-corroborated match reads as the
  # most doubtful one.
  defp confidence(candidates, author) do
    candidates
    |> group_agreeing()
    |> Enum.map(fn [held | _rest] = group -> {group_score(group), held} end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> decide(author)
  end

  # Folded, not grouped by key: agreement is a predicate and not an
  # equivalence, since a record naming no narrator agrees with both sides.
  defp group_agreeing(candidates) do
    Enum.reduce(candidates, [], fn candidate, groups ->
      case Enum.find_index(groups, fn [held | _rest] -> agrees?(held, candidate) end) do
        nil -> groups ++ [[candidate]]
        index -> List.update_at(groups, index, &(&1 ++ [candidate]))
      end
    end)
  end

  defp group_score(group) do
    best = group |> Enum.map(&(&1["score"] || 0.0)) |> Enum.max()
    bonus = if length(group) > 1, do: @agreement_bonus, else: 0.0

    min(best + bonus, 1.0)
  end

  # How far ahead the best has to be for the runner-up to stop counting as
  # doubt at all.
  @decisive 0.3

  # A best at or above this has decisively answered the query, which is what
  # lets a distinct-titled runner-up stop being a rival (below).
  @settled_score 0.95

  # What remains of the runner-up penalty when the runner-up is a catalogue
  # sibling. Not zero: a similarity match still ranks under an ASIN's 1.0.
  @sibling_discount 0.25

  # Word pairs at or above this could be one word misspelled, pluralized or
  # re-spelled; below it they are different words.
  @confusable_word 0.84

  defp decide([], _author), do: 0.0
  defp decide([{only, _held}], _author), do: only

  # A close second is doubt; a distant one is just the rest of the list.
  # Keyed on the gap between best and second, not their ratio, which would
  # charge every runner-up something. The curve holds near full value while
  # the gap is small and falls away as it approaches decisive.
  #
  # The gap alone cannot tell a rival from a catalogue sibling, since series
  # books share most of their words by construction; `rival?/3` is that test.
  defp decide([{best, best_held}, {second, second_held} | _rest], author) do
    gap = best - second

    penalty =
      if gap >= @decisive,
        do: 0.0,
        else: 0.5 * (1.0 - :math.pow(gap / @decisive, 2))

    penalty =
      if rival?(best, best_held, second_held, author),
        do: penalty,
        else: penalty * @sibling_discount

    (best * (1.0 - penalty))
    |> max(0.0)
    |> min(best)
    |> Float.round(3)
  end

  defp rival?(best_score, best_held, second_held, author) do
    best_score < @settled_score or
      (confusable?(best_held["title"], second_held["title"]) and
         not author_adjudicated?(best_held, second_held, author))
  end

  # Two same-titled books by plainly different authors are told apart by the
  # query's author; two spellings of one surname are not plainly different.
  @distinct_author 0.7

  # Guarded on `:match`, never on a similarity threshold: nil compares as
  # greater than any number in Elixir's term order.
  defp author_adjudicated?(best, second, author) do
    is_binary(author) and
      author_agreement(best["authors"] || [], author) == :match and
      cross_author_similarity(best, second) < @distinct_author
  end

  defp cross_author_similarity(one, other) do
    for a <- one["authors"] || [], b <- other["authors"] || [] do
      similarity(a, b)
    end
    |> Enum.max(fn -> 1.0 end)
  end

  # Whether two titles could be one title written two ways, rather than two
  # books sharing most of their words. Word by word, not Jaro over the whole
  # string, which a shared prefix dominates. Articles drop first so "The
  # Martian" and "Martian" align.
  defp confusable?(one, other) when is_binary(one) and is_binary(other) do
    a = title_words(one)
    b = title_words(other)

    length(a) == length(b) and
      Enum.zip(a, b)
      |> Enum.all?(fn {x, y} -> String.jaro_distance(x, y) >= @confusable_word end)
  end

  # A candidate with no title stated is not evidence the titles differ.
  defp confusable?(_one, _other), do: true

  @doc """
  The exact-identity form of a title: case, punctuation, edition words and
  leading articles do not make a different book. Deliberately exact beyond
  that, for use where linking demands identity rather than similarity.
  """
  def title_key(title) when is_binary(title), do: title |> title_words() |> Enum.join(" ")

  defp title_words(title) do
    title
    |> normalize()
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 in ["the", "a", "an"]))
  end

  # Matching the library is a different question from searching it: a
  # substring search asks whether one whole string appears inside one field,
  # and a tag title is rarely the library's title. The failure is invisible,
  # because an empty local list looks like "you don't have this book".
  #
  # Keyword matching makes a term that misses cost nothing, so asking under
  # both titles is free recall; `@offer_local` decides what is worth showing.
  defp local_books(%{title: nil}), do: []

  defp local_books(hints) do
    # One phrase, not tokens: `plainto_tsquery` splits, folds accents, stems
    # and drops stop words.
    books =
      [hints.title, hints.release_title, hints.author, hints.series]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> Books.match_books(@candidate_limit)

    Enum.map(books, fn book ->
      %{
        "source" => "local",
        "id" => book.id,
        "title" => book.title,
        "authors" => Enum.map(book.authors || [], & &1.name),
        "series" => series_refs(book.series),
        "published" => book.published && Date.to_iso8601(book.published),
        # Plain similarity: local Books are their own list, and the score
        # only decides whether the match is worth offering.
        "score" =>
          score(
            book.title,
            Enum.map(book.authors || [], & &1.name),
            nil,
            nil,
            series_refs(book.series),
            hints
          )
      }
    end)
    |> Enum.filter(&offer?(&1, hints))
    |> Enum.sort_by(& &1["score"], :desc)
  end

  # Two roads onto the form. Over the similarity floor a candidate still
  # needs its name substantially present in what the file calls itself, or
  # jaro noise plus a shared author offers an unrelated book by the same
  # writer. A candidate found through a series label is offered whatever its
  # score, because a shelf label scores nothing against the real title while
  # naming exactly that book.
  defp offer?(candidate, hints) do
    (candidate["score"] >= @offer_local and title_evidence?(candidate, hints)) or
      series_label_evidence?(candidate, hints)
  end

  # Similarity is not evidence of identity: jaro gives ~0.5 to unrelated
  # titles and a shared author adds its quarter share. What counts is the
  # book's own name appearing substantially in what the file calls itself —
  # every word of a short name, at least two of a long one.
  #
  # From the title and release name, never the series tag: a series named
  # after its first book would smuggle that book's whole title in here.
  defp title_evidence?(candidate, hints) do
    wanted =
      [hints.title, hints.release_title]
      |> Enum.flat_map(&keywords/1)
      |> MapSet.new()

    substantial?(candidate["title"], wanted) or series_label_evidence?(candidate, hints)
  end

  defp series_label_evidence?(candidate, hints) do
    wanted =
      [hints.title, hints.release_title, hints.series]
      |> Enum.flat_map(&keywords/1)
      |> MapSet.new()

    Enum.any?(
      candidate["series"] || [],
      &(substantial?(&1["name"], wanted) and series_label?(&1["name"], hints) and
          not wrong_volume?(&1, hints))
    )
  end

  # A label naming volume four is not a reason to offer volume one, however
  # famous it is. No number on either side stays neutral.
  defp wrong_volume?(entry, %{series_number: number}) when not is_nil(number) do
    case single_number(entry["number"]) do
      nil -> false
      position -> not same_number?(position, number)
    end
  end

  defp wrong_volume?(_entry, _hints), do: false

  @doc """
  Splits a phrase into the words worth comparing on.

  Not a search — `Ambry.Search.Query` does that. This is for the set
  comparisons below, where a file's label and a candidate's name are reduced
  to word sets and asked how much they share.

  Punctuation goes, and so do the words every title contains, which would
  otherwise count as agreement with everything in the library.
  """
  @stopwords ~w(a an and at by for from in of on or the to with)

  def keywords(nil), do: []

  def keywords(phrase) when is_binary(phrase) do
    phrase
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 2))
    |> Enum.uniq()
  end

  defp substantial?(name, wanted) do
    words = keywords(name)
    shared = Enum.count(words, &MapSet.member?(wanted, &1))
    words != [] and shared >= min(2, length(words))
  end

  # A series name is only evidence when the file's label IS the series.
  # Where the label has its own title words the candidate must match on
  # those, or every same-series sibling matches by construction.
  @label_filler ~w(book books bk vol volume volumes part parts no saga series)

  defp series_label?(series_name, hints) do
    series_words = series_name |> keywords() |> MapSet.new()

    [hints.title, hints.release_title]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn label ->
      label
      |> keywords()
      |> Enum.reject(
        &(MapSet.member?(series_words, &1) or &1 in @label_filler or
            Regex.match?(~r/^\d+$/, &1))
      )
      |> Kernel.==([])
    end)
  end

  defp provider_books(_level, nil, _hints, _opts), do: {[], []}

  defp provider_books(level, query, hints, opts) do
    [level: level, capability: :book_search]
    |> Registry.enabled()
    |> Enum.map(&search_provider(&1, query, hints, opts))
    |> Enum.reduce({[], []}, fn {candidates, outcome}, {all, outcomes} ->
      # nil where the provider was never asked.
      {all ++ candidates, outcomes ++ List.wrap(outcome)}
    end)
  end

  # One provider being down costs its results only, but the outcome is
  # recorded either way.
  defp search_provider(entry, query, hints, opts) do
    case search_books(entry, query, opts) do
      {:ok, books} ->
        candidates =
          books |> Enum.take(@candidate_limit) |> Enum.map(&provider_candidate(&1, entry, hints))

        {candidates, Outcome.ok(entry, length(candidates))}

      # What answered is matched on; what didn't sends `RunMatch` round again.
      {:partial, books, reason} ->
        candidates =
          books |> Enum.take(@candidate_limit) |> Enum.map(&provider_candidate(&1, entry, hints))

        Logger.warning(fn ->
          "Auto-match: #{entry.id} partial for #{inspect(to_string(query))}: #{inspect(reason)}"
        end)

        {candidates, Outcome.partial(entry, length(candidates), reason)}

      {:error, reason} ->
        Logger.warning(fn ->
          "Auto-match: #{entry.id} failed for #{inspect(to_string(query))}: #{inspect(reason)}"
        end)

        {[], Outcome.from_error(entry, reason)}
    end
  end

  # A provider that finds nothing is asked again with a plainer title, since
  # a marketing subtitle can return nothing where the bare title returns the
  # book. Second rather than first, because a subtitle is sometimes the only
  # thing telling two books apart.
  defp search_books(entry, query, opts) do
    case Providers.search_books(entry.id, query, opts) do
      {:ok, []} -> retry_plainer(entry, query, opts)
      other -> other
    end
  end

  defp retry_plainer(entry, %Provider.Query{title: title} = query, opts) when is_binary(title) do
    case plainer_title(title) do
      nil -> {:ok, []}
      plainer -> Providers.search_books(entry.id, %{query | title: plainer}, opts)
    end
  end

  defp retry_plainer(_entry, _query, _opts), do: {:ok, []}

  # An edition suffix or a subtitle, both of which a catalogue title rarely
  # carries. Returns nil when there was nothing to drop, so a failed search
  # isn't repeated verbatim.
  defp plainer_title(title) do
    plainer =
      title
      |> String.replace(~r/\s*\([^)]*\)\s*$/u, "")
      |> String.split(~r/\s*:\s+/u, parts: 2)
      |> hd()
      |> String.trim()

    if plainer != "" and plainer != String.trim(title), do: plainer
  end

  @doc """
  Hints from a library record's own fields: the edit forms' analog of
  `hints/1`, ranking provider records against what the record already knows
  rather than what the files claimed.
  """
  def form_hints(fields) when is_map(fields) do
    %{
      title: presence(fields[:title]),
      author: presence(fields[:author]),
      narrator: presence(fields[:narrator]),
      series: nil,
      series_number: nil,
      part_number: nil,
      parts_total: nil,
      asin: nil,
      release_title: nil,
      # No files behind a form, and a typed narrator is a stated one, which
      # the forward scorer already handles.
      raw: nil
    }
  end

  @doc """
  Turns provider books into records, for a search run outside matching.
  """
  def records_from(books, entry, hints) do
    books |> Enum.take(@candidate_limit) |> Enum.map(&provider_candidate(&1, entry, hints))
  end

  defp provider_candidate(book, entry, hints) do
    authors = Enum.map(book.authors || [], & &1.name)
    narrators = Enum.map(book.narrators || [], & &1.name)
    series = series_refs(book.series)

    %{
      "source" => "provider:#{entry.id}",
      "provider_name" => entry.display_name,
      "id" => book.id,
      "asin" => book.asin,
      "title" => book.title,
      "authors" => authors,
      "narrators" => narrators,
      "series" => series,
      "published" =>
        book.published && book.published.date && Date.to_iso8601(book.published.date),
      # Not derivable from the date: year-only knowledge arrives as a literal
      # January 1st, which must not render as a real release day.
      "published_format" => book.published && to_string(book.published.display_format),
      "publisher" => book.publisher,
      "cover_url" => book.cover_url,
      "description" => book.description,
      "score" => score(book.title, authors, narrators, book.asin, series, hints)
    }
  end

  # A membership is a name AND a position. Maps rather than two parallel
  # lists, so a book at #10.5 in one series and #3 in another survives.
  defp series_refs(series) do
    for entry <- List.wrap(series), is_binary(entry.name) do
      %{"name" => entry.name, "number" => number_string(entry.number)}
    end
  end

  defp number_string(nil), do: nil
  defp number_string(%Decimal{} = number), do: Decimal.to_string(number, :normal)
  defp number_string(number), do: presence(to_string(number))

  # An ASIN match is identity, not similarity — nothing else can earn 1.0.
  defp score(_title, _authors, _narrators, asin, _series, %{asin: asin}) when is_binary(asin),
    do: 1.0

  defp score(title, authors, narrators, _asin, series, hints) do
    {title_similarity, penalty} =
      case series_identity(series, hints) do
        # Identity, not similarity: the label was never the title, so its
        # title score is noise. Companion markers still subtract.
        :match ->
          {1.0, companion_penalty(title)}

        # A candidate at a different number is the wrong sibling however the
        # strings score.
        :conflict ->
          {sim, penalty} = title_parts(title, hints.title)
          {sim, penalty * @series_mismatch}

        :unstated ->
          title_parts(title, hints.title)
      end

    base =
      case author_agreement(authors, hints.author) do
        :match -> min(title_similarity * 1.05, 1.0)
        :conflict -> title_similarity * @author_mismatch
        :unstated -> title_similarity
      end

    # The narrator only speaks when both sides have one, so this does nothing
    # at the work level and is decisive at the recording level.
    base
    |> apply_narrator(narrators, hints.narrator)
    |> Kernel.*(penalty)
    |> Float.round(3)
  end

  # A candidate whose head is the queried title is that title written out in
  # full, so it scores as exact with no length penalty; otherwise the length
  # penalty scores the right book like a study guide.
  #
  # Both directions, since either side may carry the subtitle, and asymmetric
  # containment rather than a shared prefix. Companion markers still subtract.
  defp title_parts(title, wanted) do
    if is_binary(wanted) and head_match?(title, wanted),
      do: {1.0, companion_penalty(title)},
      else: {similarity(title, wanted), title_penalty(title, wanted)}
  end

  defp head_match?(title, wanted) do
    head = title_head(title)
    wanted_head = title_head(wanted)

    (head != title and normalize(head) == normalize(wanted)) or
      (wanted_head != wanted and normalize(wanted_head) == normalize(title))
  end

  # Before the first subtitle separator: a colon, or a spaced dash. A hyphen
  # inside a word ("Wild-Built") is not one.
  defp title_head(title) when is_binary(title) do
    title |> String.split(~r/\s*:\s|\s+[-–—]\s+/u, parts: 2) |> hd()
  end

  defp title_head(other), do: other

  # Whether the file's label and this candidate's series membership answer
  # each other. Three-valued, like every "didn't say" in this module:
  #
  #   :match     the label names a series and a number, and the candidate is
  #              at that number in a series whose name the label contains
  #   :conflict  same series, single-number position, different number
  #   :unstated  no label number, no matching series entry, or a position
  #              that isn't a single number ("1-4" box sets stay neutral)
  defp series_identity(series, %{series_number: number} = hints) when not is_nil(number) do
    label_words =
      [hints.title, hints.series]
      |> Enum.flat_map(&keywords/1)
      |> MapSet.new()

    series
    |> List.wrap()
    |> Enum.find(fn entry ->
      words = keywords(entry["name"])
      words != [] and Enum.all?(words, &MapSet.member?(label_words, &1))
    end)
    |> case do
      nil ->
        :unstated

      entry ->
        case single_number(entry["number"]) do
          nil -> :unstated
          position -> if same_number?(position, number), do: :match, else: :conflict
        end
    end
  end

  defp series_identity(_series, _hints), do: :unstated

  defp single_number(value) do
    case Decimal.parse(to_string(value || "")) do
      {decimal, ""} -> decimal
      _range_or_junk -> nil
    end
  end

  defp same_number?(one, other) do
    case single_number(other) do
      nil -> false
      decimal -> Decimal.equal?(one, decimal)
    end
  end

  defp presence_number(value) do
    case single_number(value) do
      nil -> nil
      decimal -> decimal
    end
  end

  # Filename first: release names are precise about parts where tag titles
  # are messy.
  defp part_hint(%ReleaseName{parts_total: total} = parsed, _tag_parsed) when is_integer(total),
    do: {parsed.part_number, total}

  defp part_hint(_parsed, %ReleaseName{parts_total: total} = tag_parsed) when is_integer(total),
    do: {tag_parsed.part_number, total}

  defp part_hint(_parsed, _tag_parsed), do: nil

  # A file tagged `part=1` feeds the tags' series_number field. When the
  # number agrees with the detected part and nothing names a series, the
  # number is the part's.
  defp suppress_part_polluted_series_number(nil, _part, _series), do: nil
  defp suppress_part_polluted_series_number(number, nil, _series), do: number

  defp suppress_part_polluted_series_number(number, {part_number, _total}, series) do
    if !(is_nil(series) and is_integer(part_number) and
           Decimal.compare(number, Decimal.new(part_number)) == :eq),
       do: number
  end

  defp apply_narrator(score, narrators, narrator) when narrators in [nil, []] or is_nil(narrator),
    do: score

  # Near-binary rather than blended, because jaro is useless on names: two
  # unrelated ones still score around 0.5. Agreement is a modest boost;
  # disagreement is decisive.
  defp apply_narrator(score, narrators, narrator) do
    match = narrators |> Enum.map(&similarity(&1, narrator)) |> Enum.max(fn -> 0.0 end)

    if match >= @narrator_match do
      min(score * 1.05, 1.0)
    else
      score * @narrator_mismatch
    end
  end

  # Titles that contain what we asked for plus a pile of other words are the
  # failure jaro cannot see. A companion marker is decisive; sheer extra
  # length is softer evidence and scales.
  defp title_penalty(nil, _wanted), do: 1.0
  defp title_penalty(_title, nil), do: 1.0

  defp title_penalty(title, wanted) do
    companion_penalty(title) * length_penalty(title, wanted)
  end

  # Deliberately NOT stripped by `normalize/1`, which would make a study guide
  # match its subject *better*. They have to subtract.
  @companion_markers [
    "study guide",
    "graphic novel",
    "summary",
    "analysis",
    "companion",
    "workbook",
    "sparknotes",
    "cliffsnotes",
    "boxed set",
    "box set",
    "collection",
    "omnibus",
    "trilogy",
    "bundle",
    "complete series",
    "unofficial"
  ]

  # Spaces removed on both sides, or a marker spelled as two words evades it.
  defp companion_penalty(title) do
    condensed = title |> normalize() |> String.replace(" ", "")

    if Enum.any?(@companion_markers, &String.contains?(condensed, String.replace(&1, " ", ""))),
      do: @companion_factor,
      else: 1.0
  end

  # Words in the candidate that aren't in what we asked for. A lot means a
  # different book that merely mentions this one.
  defp length_penalty(title, wanted) do
    candidate_words = title |> normalize() |> String.split(" ", trim: true)
    wanted_words = wanted |> normalize() |> String.split(" ", trim: true) |> MapSet.new()

    case candidate_words do
      [] ->
        1.0

      words ->
        extra = Enum.count(words, &(not MapSet.member?(wanted_words, &1)))
        max(1.0 - extra * @extra_word_cost, @min_length_factor)
    end
  end

  @doc """
  Whether a candidate's authors and the file's answer each other.

  Three-valued, and **by shared name token, not by jaro**, which cannot tell a
  name variant from a different human:

      "J.R.R. Tolkien" vs "John Ronald Reuel Tolkien"   0.573   same person
      "Daily  Books"   vs "Andy Weir"                   0.519   unrelated

  `:unstated` covers both sides being silent and a name that reduces to
  nothing comparable.
  """
  def author_agreement(authors, author) do
    wanted = name_tokens(author)
    stated = authors |> List.wrap() |> Enum.map(&name_tokens/1) |> Enum.reject(&Enum.empty?/1)

    cond do
      Enum.empty?(wanted) or stated == [] -> :unstated
      Enum.any?(stated, &(not MapSet.disjoint?(&1, wanted))) -> :match
      true -> :conflict
    end
  end

  # Single letters are dropped: initials match everything, so "J. Smith" and
  # "J. Jones" would agree on "j".
  defp name_tokens(name) do
    name |> tokens() |> Enum.reject(&(String.length(&1) < 2)) |> MapSet.new()
  end

  defp similarity(nil, _other), do: 0.0
  defp similarity(_string, nil), do: 0.0

  defp similarity(string, other) do
    String.jaro_distance(normalize(string), normalize(other))
  end

  # Accents fold as `person_key/1` folds them: this is an identity
  # comparison, so a fold it does not do is a twin it cannot see.
  defp normalize(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/\b(unabridged|abridged|a novel|audiobook)\b/, " ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp stringify_hints(hints) do
    Map.new(hints, fn {key, value} -> {to_string(key), value} end)
  end

  defp first(nil), do: nil
  defp first([]), do: nil
  defp first([value | _rest]), do: presence(value)
  defp first(value), do: presence(value)

  # A cast label is not a reader. Left out of the hints entirely, so it can
  # neither cost a candidate its narrator score nor raise a conflict.
  defp stated_narrator(narrators) do
    narrators
    |> List.wrap()
    |> Enum.reject(&placeholder_narrator?/1)
    |> first()
  end

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(_other), do: nil
end
