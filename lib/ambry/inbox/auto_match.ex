defmodule Ambry.Inbox.AutoMatch do
  @moduledoc """
  Proposes what an inbox item is, so confirming it can be one click.

  ## Three matches, not one

  An item needs a **work** match (which Book — title, authors, series), a
  **recording** match (which Media — narrators, cover, chapters, release date)
  and a **people** match (who the credited humans are — face, biography).
  They use different keys and fail independently: an ASIN identifies a
  recording outright, title-and-author identifies a work fuzzily, a name
  identifies a person and nothing else does — and you can land the right work
  with the wrong recording (a dramatized adaptation instead of the standard
  narration) or the right recording under the wrong work. So each gets its own
  candidates and its own failure mode.

  The three run in that order because each one's answer is the next one's
  question. The work's editions are the most direct route to its recordings;
  the work names its authors and the recording names its readers, and until a
  record has been found there is no cast to ask about at all.

  Nothing is applied. This writes proposals onto the inbox item; the operator
  imports, and import is what creates records.

  ## Why the whole ranked list is kept

  Storing only the winner would make "what else did it find?" a fresh round
  of provider calls every time the operator looked. The full list, with each
  candidate's score and the query that produced it, makes reviewing
  alternatives instant — and leaves re-searching for the case it's actually
  for, where the right answer isn't in the list at all.

  ## Provider records are evidence, local Books are an outcome

  A record from Hardcover and a record from rreading-glasses for one book are
  two databases describing the same thing, not two rival identities — they are
  kept as separate records and both may feed the import. A Book already in the
  library is categorically different: linking to it creates nothing, inherits
  its curation, and is what stops a second recording splitting the library. So
  local hits live in their own list (`"local"`), never ranked among the
  provider records.
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

  require Logger

  @candidate_limit 8

  # How similar a Book has to be before it is worth *showing* as "you may
  # already have this". Keyword matching recalls far more than the old
  # substring search did, so without a floor the question came with plausible
  # nonsense attached — Anne of Green Gables offered as a candidate for
  # Leviathan Wakes, on the strength of one shared word.
  #
  # Tuned for precision rather than recall on purpose: the form now has a
  # library search the operator can drive by hand, so a miss costs a search
  # and a false offer costs trust in the whole list. It deliberately does NOT
  # reach far enough to connect a file tagged "Philosopher's Stone" to a Book
  # called "Sorcerer's Stone" — that is a real case, and the operator's call.
  @offer_local 0.5

  # How many records about the *same* thing are worth a follow-up call each
  # (details, editions). Two databases holding a record of one book is normal;
  # eight of them saying it is not, and past a few the extra requests buy
  # nothing.
  @group_limit 4

  # Corroboration bonus when two providers independently return the same work.
  @agreement_bonus 0.05

  # What a companion-work marker ("study guide", "graphic novel") costs. Harsh
  # on purpose: these are reliably NOT the book being imported, and leaving
  # them near the top of the list is what made the candidate list untrustworthy.
  @companion_factor 0.25

  # Per-word cost for content the query didn't ask for, and the floor it
  # can't push a title below.
  @extra_word_cost 0.08
  @min_length_factor 0.4

  # What counts as the same reader, and what it costs to be a different one.
  @narrator_match 0.85
  @narrator_mismatch 0.5

  # What it costs to be by somebody else. Decisive rather than blended, for
  # exactly the reason the narrator is — see `author_agreement/2`.
  @author_mismatch 0.5

  # What it costs to sit at a different number in the series the label named.
  @series_mismatch 0.5

  @doc """
  Builds work and recording proposals for an item.

  Returns the attrs to store; never raises, and degrades to whatever it could
  find — a provider being down means fewer candidates, not a failed item.
  """
  def match(%InboxItem{} = item, opts \\ []) do
    hints = hints(item)
    {work, recording} = settle_levels(hints, opts)

    %{
      matches: %{
        "work" => work,
        "recording" => recording,
        # People are the third level, and they come last because they are the
        # one thing neither of the others could ask about first: a file's tags
        # name a narrator, but the *cast* only exists once a record has been
        # found. The work names its authors, the recording names its readers.
        "people" => match_people(work, recording, item.tags || %{}, opts),
        "hints" => stringify_hints(hints)
      }
    }
  end

  # **Matching is a loop, not a pipeline: evidence changes the question.**
  # A round's records can hold a better query than the one they were found
  # with — the file's label was never the book's title — and re-asking with
  # it is what settles the shelf-label releases nothing else rescues.
  #
  # The refinement gate is the loop's whole safety argument, and it is
  # **corroboration, not similarity**: gating on the score is circular,
  # because scoring low is exactly what a shelf-label title causes. Measured
  # on the operator's Wayfarers file: round 1's "winner" is a single-source
  # series omnibus at 0.594, while Hardcover's work record and Audible's
  # recording record — independent databases, independently queried — both
  # answer "The Long Way to a Small, Angry Planet", at 0.245 and 0.123. Two
  # search engines doing semantic work and landing on one answer is evidence
  # the scorer cannot see; one provider's top hit is not. Refined, the round
  # 2 query returns the work at 1.0 (measured: confidence 0.368 → 1.0).
  #
  # Rounds only ever add evidence, questions are deduped against `seen`, and
  # `@max_rounds` is the backstop — in practice one refinement settles it.
  @max_rounds 3

  # Refinement only runs for a work still under Seed's adoption bar: a
  # confident round 1 has nothing to fix.
  @refine_below 0.65

  defp settle_levels(hints, opts) do
    work = match_work(hints, opts)

    # The recording level is given the matched work, because a work's own
    # edition list is a third key alongside searching: once we know which
    # book this is, its editions are the most direct route to the recordings
    # that exist — including ones no storefront will return.
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

  # The better query, when the evidence in hand agrees on one. Grouped
  # across BOTH levels and narrator-blind on purpose: two different
  # recordings of one work — Jim Dale's and the full cast's — corroborate
  # the WORK, and requiring their narrators to agree hid exactly that.
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

      # The STRONGEST corroborated answer decides, and only a disagreeing
      # one refines. Excluding the current-query group before ranking meant
      # that when the databases confirmed the question — "Kushiel's Chosen"
      # corroborated at 1.0 — the loop refined anyway, from the next-best
      # agreement down the list: a boxed-set omnibus both providers carry,
      # whose title then swallowed the whole trilogy's words and offered
      # book 1 as a local match. Agreement WITH the question ends the loop.
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

  # Rounds add evidence, never remove it: records and local hits merge
  # add-only under their stable refs, so nothing a human may have ticked can
  # vanish. The level's *description* — query, confidence, provider outcomes
  # — follows the latest round, which is also what the form's evidence
  # header shows via `follow_query/3`.
  defp merge_level(old, new, hints) do
    candidates = add_records(old["candidates"] || [], new["candidates"] || [])

    new
    |> Map.put("candidates", candidates)
    |> Map.put("local", add_records(old["local"] || [], new["local"] || []))
    |> Map.put("providers", merge_outcomes(old["providers"] || [], new["providers"] || []))
    |> Map.put("confidence", confidence(candidates, hints.author))
  end

  # Identity is the ref; the payload may be refreshed by a later round, and
  # the score is *derived* — a record re-found by a better query keeps the
  # better score, not the one its worse query earned it. Keeping the round-1
  # payload wholesale left the refined winner sitting at its shelf-label
  # score, and the refinement changed nothing.
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

  Keyed by `person_key/1`, one entry per distinct human — the same set the
  draft's `people` decisions cover, derived here from the records rather than
  from the draft, so an import arrives with a face and a biography already
  proposed instead of sending the operator to the person form afterwards.

  ## Local first, which is why there is no cap

  A person already in the library is never searched. That is not an
  optimisation bolted on afterwards, it is what makes searching people during
  matching affordable at all: the operator's full-cast Harry Potter credits
  fifteen actors who recur across all seven books, so without it every import
  would re-ask every provider about the same fifteen humans. With it, a
  repeating cast costs one lookup on the first book and nothing on the rest.

  The check is an exact name match, deliberately. "Do we already have them"
  has to be *certain* before it is allowed to skip asking, because being wrong
  here doesn't produce a bad candidate the operator can see and reject — it
  produces a silence, and a silence is indistinguishable from a provider
  having nobody.

  ## The same shape as the other two levels

  Records are evidence, never decisions: every plausible person from every
  provider is kept with all their photos and biographies, and which one is
  right stays a judgement. `Ambry.Metadata.PersonSearch` already gathers them
  for the form's picker — this runs the same fan-out ahead of time, in the
  background job, where nobody is waiting.
  """
  def match_people(work, recording, tags, opts \\ []) do
    work
    |> credited_people(recording, tags)
    |> Map.new(fn {name, roles} -> {person_key(name), person_result(name, roles, opts)} end)
  end

  @doc """
  How a human is referred to across the matches and the draft.

  Punctuation-insensitive: the databases disagree about the dots and spaces
  in "James S.A. Corey" and none of those spellings is a different human —
  measured on the operator's Caliban's War, two providers' spellings of the
  one pen name made two author credits, two person decisions, and a
  duplicate library author waiting at approval. `Draft.PersonDecision` keys
  are these strings, so the key IS the sameness rule for humans; anything
  asking whether two spellings mean one person must go through it. (The
  title normaliser is a different job — it also strips edition words.)
  """
  # Condensed to letters and digits alone: punctuation-insensitivity by
  # itself still left "TJ Klune" and "T.J. Klune" apart ("tj klune" vs
  # "t j klune"), and initials are exactly where providers disagree. With
  # spacing gone too, "J.K.", "J. K." and "JK" Rowling are one key — and the
  # SQL twin stays a single regexp_replace. Accents fold as well (NFD, marks
  # stripped; `unaccent()` on the SQL side): the library's "Patricia
  # Rodríguez" and a file's "Patricia Rodriguez" are one narrator, and the
  # accent was one approval away from a second person of the same name.
  def person_key(name) when is_binary(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
  end

  @doc """
  The photo and biography to propose for one credited human.

  Everything the providers returned is kept as evidence; this is the
  *proposal* laid on top of it, so an import arrives with a face already
  chosen instead of a grid to work through. The operator overrides it in the
  picker, which is why it is allowed to choose at all.

  Two rules, both of them about not proposing confident nonsense:

    * **Only a candidate whose name is actually the credited name.** Provider
      person-search is recall-first — `PersonSearch.plausible?/2` admits
      anything sharing a name token, which is right for a grid a human is
      reading and wrong for an automatic choice. Measured on the operator's
      own files: Audnexus answers "Rachel Dulude" with *Rachel Aukes* first,
      and "Jefferson Mays" with Jefferson Morley, Jefferson Bethke and Thomas
      Jefferson before Wikidata's actual actor. Taking the top hit would have
      put a stranger's face on three of seven people.
    * **First provider that has something usable wins, in the operator's own
      priority order** — which is what `Registry.enabled/1` returns, so this
      inherits their preference rather than inventing one. Photo and biography
      are chosen independently, because the provider with the best portrait is
      routinely not the one with the best prose.

  An exact name is still not an identity — Wikidata knows three Jim Dales, a
  film producer, a meteorologist and a marketing adviser, none of them the
  actor who read Harry Potter. That is why this proposes rather than settles,
  and why every candidate stays on the record.
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

  # The first candidate that has one, carrying which provider it came from —
  # 1d provenance is written from this, so the value and its source have to
  # travel together or the person is recorded as hand-typed and locked.
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

  # `person_key/1` is the sameness rule for humans, and this is that rule
  # applied to two names in hand.
  defp same_human?(one, other) when is_binary(one) and is_binary(other),
    do: person_key(one) == person_key(other)

  defp same_human?(_one, _other), do: false

  # rreading-glasses returns the literal string "N/A" where it has no
  # biography, and storing that as somebody's life story is worse than leaving
  # it blank — blank is visibly unfinished, "N/A" looks decided.
  @nonsense_bios ["n/a", "na", "none", "unknown", "no description", "-", "."]

  defp usable_bio(text) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed != "" and String.downcase(trimmed) not in @nonsense_bios, do: trimmed
  end

  defp usable_bio(_other), do: nil

  defp person_result(name, roles, opts) do
    case People.people_named(name) do
      # Already ours. Nothing is searched, and nothing needs to be: the
      # library's own photo and biography are what an existing person is for.
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

  Kept away from the provider candidates for the same reason a local book is:
  it answers a different question. A provider record is evidence about a
  human; one of these *is* a human, and choosing them creates nobody.

  Shared with `Ambry.Inbox.Lookup`, which asks again when the operator
  re-searches — the held answer is about the name that was asked before, and a
  rename is exactly when that stops being true.
  """
  def local_people(name), do: name |> People.people_named() |> Enum.map(&local_person/1)

  defp local_person(person) do
    %{
      "source" => "local",
      "id" => person.id,
      "name" => person.name,
      # what the form needs to say "you already have them, and they already
      # have a face" without loading the person itself
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

  Shared with `Ambry.Inbox.Lookup`, which builds the same records when the
  operator searches a person again — it had its own copy, which is how the
  two drifted into one being scored and the other not.
  """
  def person_candidate(%PersonSearch.Match{} = match, asked_for) do
    %{
      "source" => "provider:#{match.provider_id}",
      "provider_name" => match.provider_name,
      "id" => to_string(match.id),
      "name" => match.name,
      "description" => presence(match.description),
      # what tells two same-named humans apart in a grid — TMDB's known-for
      # credits, mostly
      "note" => presence(match.note),
      "images" => match.images,
      "score" => person_score(match.name, asked_for)
    }
  end

  @doc """
  How well a returned name answers the name we asked about.

  **Not a string distance.** Jaro cannot separate a legitimate variant from a
  different human — measured, "Ty Franck" against "Tyler Corey Franck" scores
  *lower* than "Ty Franck" against a Corey mismatch — so the ordering is by
  what the names structurally share, which is the same reasoning
  `author_agreement/2` already follows:

    * `1.0` — the same name once accents and punctuation are folded away
      (`person_key/1`), so "Émile Zola" and "Emile Zola" are one person
    * `0.8` — one name's words are all inside the other's: "Ty Franck" within
      "Tyler Corey Franck", the pen-name-and-full-name case
    * `0.6` — they share a word, which is the floor `PersonSearch` already
      filters at
    * `0.0` — nothing shared, which a filtered search shouldn't return

  Ties are common and are broken by usefulness rather than by nothing: a
  candidate carrying a photo and a biography is both more useful to the
  operator and more likely to be the documented human, and a stable sort
  leaves the operator's provider priority deciding the rest.
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

  # A shortening is the same word: "Ty" is how Tyler Corey Franck is credited,
  # and "Dan" is Daniel. Exact-token comparison missed exactly the case this
  # scoring exists for, which is the one `Ambry.Metadata.PersonSearch`'s
  # moduledoc names. Words under two characters were already dropped, so this
  # can't collapse initials onto everything.
  defp same_word?(word, other),
    do: String.starts_with?(word, other) or String.starts_with?(other, word)

  @doc """
  People, best answer first.

  The work and recording levels have ranked their candidates since they
  existed; the person level never did, so the list was whatever order the
  providers happened to be asked in — and the operator saw plainly wrong
  humans above the right one.

  **Every candidate is scored against the name being asked about now**, not
  only the ones arriving without a score. A score is the answer to "how well
  does this record answer the name we are asking about", and a re-search is
  the operator changing the question: looking up "David Wong" and then Jason
  Pargin left the David Wong records wearing the 100% they earned under the
  old question, sitting above the humans actually searched for. Nothing is
  dropped — a record that no longer answers the question sinks, which is what
  the fold below `record_list`'s threshold is for.
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

  # **Everyone any plausible reading of the evidence would credit**, which is
  # the union of what the records name and what the file's tags name — not
  # the records-else-tags fallback `Seed` applies when it builds the credits.
  #
  # The two differ exactly when a level is doubted, and that is the case this
  # has to get right. `Seed` ticks no record it doesn't believe, so a doubted
  # recording credits the *tags'* narrator: measured on the operator's Becky
  # Chambers file, the recording match is 12% and the credit created is
  # "Patricia Rodriguez" from the tags, while the top record reads "Rachel
  # Dulude". Deriving from records alone searched the wrong human and left the
  # one actually being created with no photo and no biography — the exact
  # failure this level exists to fix.
  #
  # Taking the union rather than reproducing the trust rule keeps the
  # thresholds in one place: they are `Seed`'s to own, and a second copy here
  # is the diffusion that made one invariant keep getting forgotten somewhere
  # new. Over-searching costs one cached provider call for somebody who ends
  # up uncredited; under-searching costs the import its faces.
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

  Used for three things, none of which is merging: scoring (corroboration is
  not a rival), deciding what to pre-tick, and deciding which records are
  worth a details or editions call. The records themselves stay separate rows
  — two databases holding a record of one book is the normal case.
  """
  def top_group([]), do: []

  def top_group(candidates) do
    # `Enum.max_by`, not `hd/1`. Reading the head as "the best" is only true
    # of an already-ranked list, and that assumption is invisible at the call
    # site: the media form handed over a provider-ordered list whose first
    # element was a 0.13 study guide, so the editions of a *study guide* were
    # fetched and the book's were not.
    best = Enum.max_by(candidates, &(&1["score"] || 0.0))

    candidates
    |> Enum.filter(&agrees?(&1, best))
    |> Enum.take(@group_limit)
  end

  @doc """
  The records worth *pre-ticking* — narrower than `top_group/1` once the file
  has said who read it.

  Ticking a record says "this describes my file", and a record naming no
  narrator cannot support that claim at the recording level. It stays in the
  group for every other purpose — it may well be the operator's edition, and
  `apply_narrator_evidence/2` deliberately never penalises it — but adopting
  its fields is a guess.

  Measured: The Martian's `B082BHWQCJ` is Wil Wheaton's edition with the role
  string missing upstream. Silent, so unpenalised, so still at 1.000, so
  ticked — and it handed the operator's 2013 R.C. Bray recording Wheaton's
  2020 release date as a conflict.

  Only bites when some record IS corroborated. With nothing to go on — the
  ordinary case across most of a library — this is `top_group/1` exactly.
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

  "Full Cast" is not a person and not a rival to one — it is a *label for* the
  cast a full-cast production credits. Taken literally it manufactured a
  narrator conflict on every dramatized edition: measured on the operator's
  Harry Potter and the Philosopher's Stone, the file's tag says `Full Cast`,
  Hardcover lists all fifteen actors, and the form reported "The file says
  Full Cast reads this; the closest catalogue entry is read by Hugh Laurie,
  Matthew Macfadyen, … Those are different recordings of the same book."
  They are the same recording, described two ways.

  Same principle as `agrees?/2`: **a placeholder is "didn't say", not "said
  something different"** — so it stops arguing with the catalogue instead of
  being scored against it, and it never becomes a Person either.
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

  Tags win because they're vastly more reliable — measured across a real
  library, 96% of releases carry a title and author in tags, against 55%
  whose *name* yields an author.
  """
  def hints(%InboxItem{} = item) do
    tags = item.tags || %{}
    parsed = ReleaseName.parse(item.path)
    tag_parsed = ReleaseName.parse(tags["book_title"] || "")
    part = part_hint(parsed, tag_parsed)

    %{
      # The tag title is stripped of release junk before it becomes a query:
      # "Children of Time (Unabridged)" searches measurably worse than the
      # bare title, and because it still returns *something*, the zero-result
      # plainer-title retry never rescues it. The verbatim tag stays on offer
      # as a chip — this cleans the question, not the evidence.
      title: ReleaseName.strip_noise(tags["book_title"]) || parsed.title,
      author: first(tags["authors"]) || parsed.author,
      narrator: stated_narrator(tags["narrators"]) || parsed.narrator,
      series: presence(tags["series"]) || parsed.series,
      # The number beside the label, wherever it was written: the tags'
      # series_number field, the tag title's own tail ("Wayfarers, Book 4"),
      # or the folder name. A label naming a series and a number is an
      # *identity* — see `series_identity/2` — and it is also the only thing
      # that stops a label-tagged later volume matching the series' famous
      # first book.
      series_number:
        suppress_part_polluted_series_number(
          presence_number(tags["series_number"]) ||
            tag_parsed.series_number ||
            parsed.series_number,
          part,
          presence(tags["series"]) || parsed.series
        ),
      # The release's place in a part set ("Part 1 of 2"), from the file
      # name first — GraphicAudio names releases precisely, tag titles are
      # messier — and the tag title's tail second.
      part_number: part && elem(part, 0),
      parts_total: part && elem(part, 1),
      asin: presence(tags["asin"]) || parsed.asin,
      # Kept **beside** `title` rather than folded into it. The tags win the
      # hint because they are the more reliable field, but the name is a real
      # second opinion and the form has to be able to offer it — measured on
      # the operator's library, the two disagree on 105 of 198 releases, and
      # neither is reliably the better one. `title` is what gets searched and
      # scored; this is what gets proposed.
      release_title: parsed.title,
      # Everything the item says about itself, **unparsed**. The fields above
      # are what gets searched; this is what a candidate gets checked back
      # against, and it exists because parsing is precisely what fails in the
      # cases that matter. `Weir Andy - The Martian (R.C. Bray) - 2013` names
      # its narrator in a shape no field captures — `extract_narrator/1` only
      # knows "(read by X)" — so `narrator` comes out nil, the narrator scorer
      # no-ops, and Wil Wheaton's edition takes the item at 1.0.
      raw: raw_text(item)
    }
  end

  # Basenames only: the parent directories are the source root, which is the
  # operator's filesystem layout and says nothing about this release.
  defp raw_text(%InboxItem{} = item) do
    [Path.basename(item.path || "")]
    |> Enum.concat(Enum.map(item.files || [], &Path.basename/1))
    |> Enum.concat(tag_text(item.tags))
    |> Enum.join(" ")
  end

  defp tag_text(tags) when is_map(tags) do
    tags |> Map.values() |> List.flatten() |> Enum.filter(&is_binary/1)
  end

  defp tag_text(_tags), do: []

  # Local Books are kept in their own list, not ranked among the provider
  # records. Reusing a Book you already have and importing one you don't are
  # different *outcomes* — one creates nothing, inherits the book's curation
  # and adds an alternate edition — while a provider record is *evidence*
  # about a book. Ranking them together made the form ask one question that
  # was really two.
  defp match_work(hints, opts) do
    query = work_query(hints)

    {candidates, outcomes} = provider_books(:work, query, hints, opts)

    query
    |> level_result(candidates, outcomes, hints.author)
    |> Map.put("local", local_books(hints))
    |> hydrate_top(opts)
  end

  # A search hit is a summary, not the record. Measured against
  # rreading-glasses, `search_books` returns a work carrying **one** edition
  # while `book_details` returns the same work with **seventeen** — along with
  # the fuller description and a cover the search result may lack. Seeding the
  # draft from the summary meant importing a thinner book than the provider
  # actually knew about.
  #
  # Every record about the top work is hydrated, not just the single best one:
  # they all feed the field candidates, so a thin one means the operator can't
  # take rreading-glasses' description after all. Records about *other* works
  # stay thin until ticked — nobody has said they're relevant yet.
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
    # One chip per provider however many of its records were hydrated: asking
    # Hardcover about four of its own works is four calls but one answer.
    |> Map.put("providers", merge_outcomes(result["providers"] || [], tally(failures)))
  end

  defp hydrate_top(result, _opts), do: result

  @doc "How a record is referred to: its provider and that provider's id."
  def ref(record), do: {record["source"], to_string(record["id"])}

  @doc """
  Marks a record as having had its full details fetched.

  Records about the top work are hydrated while matching; the rest stay thin
  until the operator ticks one, since nothing has suggested they're relevant
  and their description and cover aren't wanted until they are.
  """
  def hydrated(record), do: Map.put(record, "hydrated", true)

  @doc """
  Everything a provider knows about one record, for filling in a thin search
  hit.

  A search result is a summary: measured against rreading-glasses, `search`
  returns a work carrying **one** edition while `book_details` returns the same
  work with **seventeen**, plus the fuller description and a cover the summary
  may lack.
  """
  def details(record, opts \\ []) do
    {record, _outcome} = details_with_outcome(record, opts)
    record
  end

  @doc """
  The same fetch, plus a failed outcome when the provider couldn't be reached.

  **A thin record and an unfetched record are not the same thing**, and this
  is the difference. Leaving the summary in place is still the right
  behaviour — it is a usable candidate, and one enrichment call failing must
  not fail an item that otherwise matched — but doing it *quietly* meant a
  rate-limited details call cost the record its description, its cover, its
  publisher and its edition list with nothing anywhere saying so. Measured on
  a cold scan of 353 releases, the shared rreading-glasses instance 429'd
  about 6% of requests, none of which surfaced.

  The outcome is what makes it visible and what makes it come back:
  `RunMatch` fails a job with any unreached provider, and provider errors are
  never cached, so the retry re-asks exactly this call.
  """
  def details_with_outcome(record, opts \\ []) do
    case details_for(record, opts) do
      # Not a provider record, or a provider the registry doesn't know: there
      # is nothing to report and nothing a retry could do.
      :no_provider ->
        {record, nil}

      {:ok, entry, fuller} ->
        # Success is reported too, and it has to be: outcomes replace each
        # other by id, so a details call that only ever spoke up when it
        # failed would leave "couldn't be reached" on the chip forever, even
        # after the retry that fixed it.
        {record |> Map.merge(fuller) |> hydrated(), Outcome.ok(entry, 1, :details)}

      # nil when the provider was never asked — it implements no details call,
      # or it is switched off. `retry/4` and the hydrate path both drop it.
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
        # Only fields the summary can be *missing*. The title, authors and
        # score stay as matched — re-deriving them here would silently move
        # what the operator already saw ranked.
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

  # An ASIN is a recording-level key, so when there is one it *is* the query:
  # a hit on it is definitive in a way no title match ever is.
  defp match_recording(%{asin: asin} = hints, work, opts) when is_binary(asin) do
    query = %Provider.Query{keywords: asin}
    {candidates, outcomes} = provider_books(:recording, query, hints, opts)
    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints, opts)

    level_result(
      query,
      candidates |> Kernel.++(editions) |> dedupe_records() |> apply_narrator_evidence(hints),
      outcomes ++ edition_outcomes,
      hints.author
    )
  end

  # Structured, not concatenated. Audible's catalog matches `title` against
  # the title alone, so the old `"#{title} #{author}"` string searched for a
  # book literally called that and returned nothing — the recording level came
  # up empty on every single item. The narrator goes in too: it is the field
  # that tells two recordings of one work apart.
  defp match_recording(hints, work, opts) do
    query = %Provider.Query{
      title: hints.title,
      author: hints.author,
      narrator: hints.narrator
    }

    {candidates, outcomes} = provider_books(:recording, query, hints, opts)
    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints, opts)

    level_result(
      query,
      candidates |> Kernel.++(editions) |> dedupe_records() |> apply_narrator_evidence(hints),
      outcomes ++ edition_outcomes,
      hints.author
    )
  end

  @doc """
  Collapses records **one provider** returned more than once.

  Not the same thing as fusing two providers' records, which this module
  refuses to do and should keep refusing: those are two databases describing
  one book, each knowing something the other doesn't. This is one database
  holding the same edition four times. Measured on The Martian, Hardcover
  returns R.C. Bray's recording on four rows and Wil Wheaton's on four more,
  differing only in which fields are filled — and with `@candidate_limit` at
  #{@candidate_limit}, those eight rows crowd genuine alternatives (the German
  and Swedish recordings) off the list entirely.

  Two rules keep it from doing harm:

    * **Merge, don't drop.** The duplicates are not identical — of Wheaton's
      four rows only one carries an ASIN — so the survivor takes the union,
      filling its blanks from the rows it absorbs. Picking a winner and
      discarding the rest threw away the ASIN roughly three times in four.
    * **First occurrence keeps the identity.** A record is referred to by
      `{source, id}`, and the draft points at records by that ref. Records
      already on the item come before newly-found ones, so the ref a re-search
      might have collapsed is the one that survives — and anything the
      operator has actually ticked is pinned outright.

  Deliberately strict about what counts as the same record: same provider,
  same normalized title, the *same* set of narrators, and no disagreement on
  ASIN or publisher (one side being blank is not a disagreement). Two Audible
  ASINs for one Wheaton recording are a US and a UK edition, not a duplicate,
  and an edition crediting nobody is not evidence that it is some other
  edition's recording.
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

  # The survivor keeps everything it had and gains everything it lacked. The
  # count rides along because a provider holding four rows for one recording
  # is a fact about the provider worth being able to see, and silently tidying
  # it away is how a data-quality problem becomes invisible.
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

  Everything else here runs forwards: read the item, build a query, score what
  comes back. This runs **backwards** — take each candidate's narrators and go
  looking for them in the item's own raw text. It exists because the forward
  path has a silent hole: `hints.narrator` is nil whenever the parser couldn't
  find a credit, and `apply_narrator/3` then does nothing at all, so a
  recording by the wrong reader keeps a perfect title-and-author score.
  Measured on The Martian — tags carrying no narrator, "(R.C. Bray)" sitting in
  the filename — the item proposed **Wil Wheaton at 1.0**, unopposed.

  Three-valued, like every "didn't say" in this module, and the middle value is
  the one that matters:

    * **supported** — a candidate's reader is named in the file. Corroboration.
    * **unstated** — *no* candidate's reader is named anywhere. The file has
      said nothing about who read it, which is the ordinary case, so nothing
      is adjusted. Getting this wrong would penalise every correct match in
      the library.
    * **contradicted** — this candidate's reader is absent *while a rival's is
      present*. Only then has the file spoken: it named a reader, just not
      through any field we parse, and it isn't this one.

  Candidates carrying no narrator at all are never touched — a record that
  doesn't say who read it isn't contradicted by one that does.

  Only fires when `hints.narrator` is nil, so exactly one narrator mechanism is
  ever active: the stated credit when there is one, this when there isn't.
  Full-cast releases land here too — "Full Cast" is a placeholder, not a
  person, so `stated_narrator/1` rejects it and the forward path has nothing.
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
    # Re-derived from the untouched base every time rather than multiplied into
    # the running score: re-searching an item runs this again over records that
    # already carry a verdict, and a factor applied twice would sink a
    # candidate a little further on every visit.
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
        # Initials and mononyms carry too little to search for: "R.C." against
        # a filename would match anything with an "r" in it. "Bray" is the
        # part that identifies, and a name reduced to nothing identifies
        # nobody — so it abstains rather than guessing.
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

  This is what finds an edition a storefront has erased: Audible's catalog API
  is a storefront, not a bibliography — when rights lapse and a title is
  pulled, it vanishes from search *and* from direct ASIN lookup, with no record
  that it ever existed. Hardcover is a database of editions rather than a shop,
  so it still has it. Measured for Neuromancer: Audible 1 audio edition,
  Hardcover 7 — including a narrator Audible doesn't list at all. Measured for
  The Martian: Audible has only Wil Wheaton's re-recording, Hardcover still has
  R.C. Bray's Podium original with its ASIN.

  **Not rreading-glasses**, whatever older notes here said: its edition list
  never carries a narrator, because the Goodreads query it issues omits
  secondary contributors. At this level that makes it silent on the only
  question being asked.

  **Every capable record is asked**, not the first one. This used to be an
  `Enum.find_value` that stopped at the first editions-capable provider even
  when it returned nothing or errored, which is precisely backwards: the whole
  value here is coverage across databases.

  Run during matching over the records about the top work, and again from the
  form whenever the operator ticks a work record that hasn't been asked yet.
  The `metadata` queue is serial and retries, so a thorough match is allowed
  to take as long as it takes.
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

  # One chip per provider, not one per record asked. Asking a provider about
  # four of its own work records is four calls but one answer, and reporting
  # them separately read as nonsense: "Hardcover editions: 0 · Hardcover
  # editions: 0 · Hardcover editions: 13 · Hardcover editions: 0 …" across a
  # row. It also hid a real number — the inbox de-duplicates outcomes by id and
  # keeps the last, so a provider that found thirteen editions for one work and
  # none for the next reported **none**.
  #
  # **A failure outranks an answer.** Collapsing four calls to one chip used to
  # let any success speak for the group, so a provider that answered about
  # three works and was rate-limited on the fourth reported a clean `ok` and
  # the fourth work's editions were never seen again — the same silent miss in
  # miniature. Now the chip says "couldn't be reached" while still carrying
  # what did come back, and `RunMatch` sends the item round again for the rest.
  @doc """
  Collapses many calls to one provider into the one chip the operator reads.
  """
  def tally_outcomes(outcomes), do: tally(outcomes)

  defp tally(outcomes) do
    outcomes
    |> Enum.group_by(& &1["id"])
    |> Enum.map(fn {_id, [first | _rest] = group} ->
      answered = Enum.reject(group, &Outcome.failed?/1)
      count = Enum.sum_by(answered, &(&1["count"] || 0))

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

  # A recording is a recording of exactly one work, so an edition that came
  # out of a work's own list carries that work with it. Ticking such a
  # recording settles the book too, instead of asking the operator the same
  # question twice.
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

        # The registry is what names a provider on a chip, and an id it has
        # never heard of can't be retried anyway.
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
      # The flattened string is what the cache keys on and what text-only
      # providers see, but it isn't what was *asked* — the fields are, and
      # they're what the operator needs to read when a match looks wrong.
      "query_fields" => query_fields(query),
      "candidates" => rank(candidates),
      "confidence" => confidence(candidates, author),
      # which providers were asked, and what each said. A provider that fails
      # used to vanish silently, leaving the operator to wonder why a source
      # they had enabled contributed nothing.
      "providers" => outcomes
    }
  end

  @doc """
  Orders records best-first and caps the list.

  Records are **not** fused when two providers return the same thing. That is
  the normal case, not a duplicate to clean up: they are two databases holding
  a record of one book, and each knows things the other doesn't — one has the
  better description, the other the better cover. Collapsing them deleted the
  loser's payload and made the list look like a set of rival identities.
  """
  def rank(candidates) do
    candidates |> order_candidates() |> Enum.take(@candidate_limit)
  end

  @doc """
  Best first: by score, and among equal scores by what the file corroborated.

  The tie-break is not decoration. A supported candidate cannot out-*score* a
  silent one that was already at 1.0 — the boost is capped there — so The
  Martian ends with R.C. Bray's corroborated recording and an Audible edition
  crediting nobody both sitting at exactly 1.000. Inventing a score gap to
  separate them would be dishonest about how sure we are; ordering the
  corroborated one first is simply saying which of two equals the file
  actually spoke about.
  """
  def order_candidates(candidates) do
    Enum.sort_by(candidates, &{&1["score"] || 0.0, corroboration(&1)}, :desc)
  end

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

  # Recordings are keyed by what makes them *different recordings*. Title and
  # author identify a work; two audiobooks of one work share both and are not
  # the same thing — the 1984 Books on Tape and 2011 Penguin Audio editions of
  # Neuromancer collapsed into one candidate until the narrator and ASIN went
  # into the key.
  @doc """
  Whether two records describe the same thing.

  **Everything they both say has to agree; a field one of them doesn't carry
  is not a disagreement.** That is the whole rule, and it has to be a binary
  predicate rather than a key — the same shape `scalar/2`'s date equivalence
  needed, and for the same reason: "didn't say" is compatible with every
  answer, which no key function can express.

  Measured on Legends & Lattes, where the correct 84% Audible match was being
  reported as 54% "unsure" and left un-ticked, taking the publisher, release
  date and description down with it. Two separate reasons, both of them a
  catalogue being scored as a rival of the very audiobook it describes:

    * **A storefront id is not an identity.** Audible's record carries ASIN
      `B0B3GB64T1` and Hardcover's record of the same reading carries
      `B0B3G97QY1` — a regional variant. The ASIN used to be part of the key.
      It still *confirms* a match when it agrees (that's `score/5`'s job); it
      no longer denies one when it differs.
    * **Two of Hardcover's edition records list no narrator at all.** Keyed,
      they fell through to the work clause and could never corroborate a
      recording — so the audiobook was its own runner-up.

  Callers pass one level's candidates at a time, which is why there's no
  work/recording tag: at the work level nobody carries narrators and the
  authors decide, at the recording level the narrators do.
  """
  def agrees?(one, other) do
    same_stated_title?(one["title"] || "", other["title"] || "") and
      companion?(one["title"]) == companion?(other["title"]) and
      compatible?(one["narrators"], other["narrators"]) and
      compatible?(one["authors"], other["authors"])
  end

  # A study guide agrees with its subject on every other test, and that is not
  # a near miss — it is the three tests lining up. Its title's *head* is the
  # book's title exactly, because a companion work is named
  # "<The Book>: <something>" by construction, and head containment was built
  # for genuine subtitles. It credits no narrator and, very often, no author.
  # So all three read "didn't say", and "The Martian: A Novel by Andy Weir |
  # Unofficial Summary & Analysis" was pre-ticked onto the operator's Martian
  # while showing a score of 0.25 — the scorer knew, and nothing asked it.
  #
  # The sharpest part: the two rival companion works, which name a *different*
  # author, were correctly excluded. Only the one carrying no author data at
  # all got through, so the record with the worst data earned the most trust.
  defp companion?(title), do: companion_penalty(title || "") != 1.0

  # A title and that same title carrying its subtitle are one answer written
  # two ways: rreading-glasses says "Cast Under an Alien Sun" where Hardcover
  # writes "Cast Under an Alien Sun: Destiny's Crucible, Book 1", and exact
  # equality read the two records of one book as rivals — near-tied, so the
  # doubt penalty fired on a doubly-corroborated match. Asymmetric
  # containment, same as the seeder's `same_title?/2` and for the same
  # reason: one title has to be the WHOLE of the other's head, or "The
  # Expanse: Leviathan Wakes" agrees with "The Expanse: Caliban's War".
  #
  # Compared as `title_key/1`, not `normalize/1`: Audible says "Path of
  # Daggers" where every other catalogue says "The Path of Daggers", and the
  # bare-normalized compare read the article as a rival spelling — the
  # corroborated recording split into two groups and the doubt penalty cut a
  # five-record consensus to 0.437 while its sibling item, whose titles
  # happened to match verbatim, sat at 0.951.
  defp same_stated_title?(one, other) do
    a = title_key(one)
    b = title_key(other)

    a == b or title_key(title_head(one)) == b or title_key(title_head(other)) == a
  end

  # A record that names fewer of the same people is compatible with one that
  # names more: rreading-glasses credits As You Wish to "Cary Elwes" and
  # Hardcover to "Cary Elwes, Joe Layden", and reading that as a rival
  # doubted a match both databases had confirmed. Disjoint or crossing sets
  # stay incompatible — "said less" corroborates, "said different" does not.
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

  # Confidence is about the *decision*, not just the top hit: a strong match
  # with a genuinely different runner-up is exactly the case a human should
  # look at, so a close second pulls it down.
  #
  # Corroboration is not a rival. Records are no longer fused, so two providers
  # returning the same work are two rows — and scoring them as rivals would
  # read the best-corroborated match in the library as the most doubtful one,
  # which is the bug #1186 fixed by merging. Grouping for the score keeps that
  # fix without the merge.
  defp confidence(candidates, author) do
    candidates
    |> group_agreeing()
    |> Enum.map(fn [held | _rest] = group -> {group_score(group), held} end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> decide(author)
  end

  # Folded rather than grouped by key, because agreement is a predicate and
  # not an equivalence a key can capture — a record that names no narrator
  # agrees with one that does, and with another that doesn't.
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
  # sibling rather than a rival. Not zero: a similarity match should still
  # rank under an ASIN's flat 1.0.
  @sibling_discount 0.25

  # Word pairs at or above this could be one word misspelled, pluralized or
  # re-spelled; below it they are different words.
  @confusable_word 0.84

  defp decide([], _author), do: 0.0
  defp decide([{only, _held}], _author), do: only

  # **A close second is doubt; a distant one is just the rest of the list.**
  # The penalty used to be `0.5 * second / best`, which is a ratio and so
  # charged *every* runner-up something — measured on Legends & Lattes, a
  # doubly-corroborated 0.854 was cut to 0.576 by a different book in the same
  # series by the same author scoring 0.556. That put it under the doubt bar,
  # so nothing was adopted and the publication date fell back to the file's
  # tags, discarding the real date rreading-glasses had just supplied.
  #
  # Keyed on the *gap* instead, which is what "close" means and what the old
  # comment already claimed this did.
  # The curve matters as much as the switch to gaps. A near-tie has to stay
  # firmly doubted — "The Silent Patient" against "The Silent Patients" by
  # "Alexa Michaelides" is two different books and exactly the case for a
  # human — so the penalty holds near its full value while the gap is small
  # and falls away only as the gap approaches decisive. A straight ramp let a
  # 0.12 gap through at 0.69, over the bar that adopts a match.
  #
  # But the gap alone cannot tell a rival from a catalogue sibling. Series
  # books share most of their words by construction, so "Children of Strife"
  # sat 0.133 behind an exact, doubly-corroborated "Children of Time" — all
  # but the same gap as the Silent Patients near-tie — and dragged a certain
  # match under the doubt bar. What distinguishes them is whether the
  # operator could actually mistake one for the other (`rival?/3`): a
  # confusable title keeps the full penalty, a plainly different one is
  # discounted — *provided* the best decisively answered the query, because
  # when nothing matched well the runner-up is genuine ambiguity whatever its
  # title says.
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
  # query's author: the operator's Limitless (Alan Glynn) sat doubted at
  # 0.583 under Jim Kwik's identically-titled self-help book. With no author
  # in hand the tie is genuine ambiguity and stays doubted; and "Alex" vs
  # "Alexa" Michaelides is NOT plainly different — that near-tie must stay
  # doubted too, which is what the cross-similarity floor is for.
  @distinct_author 0.7

  # Guarded on `:match` rather than on a similarity crossing a threshold: with
  # `author_similarity/2` returning nil for a record naming nobody, `nil >=
  # 0.85` is *true* in Elixir's term order (atoms sort above numbers), so an
  # authorless candidate silently adjudicated every tie it was in.
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

  # Whether two titles could be one title written two ways — a plural, a
  # typo, a re-spelling — as opposed to two books that merely share most of
  # their words. Jaro over the whole string cannot make this distinction:
  # a shared prefix dominates it, so "children of time" vs "children of
  # strife" scores 0.924 — HIGHER than plenty of true retitlings. Word by
  # word the difference is stark: time/strife is 0.58 while
  # patient/patients is 0.96. Articles are dropped first so "The Martian"
  # and "Martian" still align.
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
  leading articles do not make a different book — the operator's two
  Princess Bride releases are titled "Princess Bride" and "The Princess
  Bride". Deliberately EXACT beyond that ("Dune Messiah" and "Dune" differ
  by it); for use where linking demands identity, not similarity.
  """
  def title_key(title) when is_binary(title), do: title |> title_words() |> Enum.join(" ")

  defp title_words(title) do
    title
    |> normalize()
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 in ["the", "a", "an"]))
  end

  # **Matching the library is a different question from searching it.** The
  # substring search behind `list_books` asks whether one whole string appears
  # inside one field, which is right for a person typing and wrong here: a tag
  # title is rarely the library's title. Measured on the operator's own
  # uploads, the file for Harry Potter and the Philosopher's Stone is tagged
  # `HP1 - The Philosopher's Stone` — a shelf label — and no substring of it
  # appears in the book's real title.
  #
  # Worse, this used to search the flattened `title author` string, which is
  # not a substring of any single field and so matched **nothing, on every
  # item carrying an author in its tags** — 96% of them, per 1b. Exactly
  # #1186's bug (a structured query flattened for something that wants one
  # field), repeated here and invisible because an empty local list looks
  # identical to "you don't have this book".
  #
  # Keywords fix both directions: a term that misses costs nothing, and the
  # author's name goes from breaking the search to improving the ranking.
  defp local_books(%{title: nil}), do: []

  defp local_books(hints) do
    # The file's name goes in too. A term that misses costs nothing here —
    # that is the whole reason this is keyword matching rather than a
    # substring search — so asking under both titles is free recall, and it is
    # the difference between finding and not finding a book whose tags call it
    # "Wayfarers, Book 1". The `@offer_local` floor still decides what is
    # worth *showing*.
    books =
      [hints.title, hints.release_title, hints.author, hints.series]
      |> Enum.flat_map(&Books.match_keywords/1)
      |> Enum.uniq()
      |> Books.match_books(@candidate_limit)

    Enum.map(books, fn book ->
      %{
        "source" => "local",
        "id" => book.id,
        "title" => book.title,
        "authors" => Enum.map(book.authors || [], & &1.name),
        "series" => series_refs(book.series),
        "published" => book.published && Date.to_iso8601(book.published),
        # No thumb on the scale any more: local Books are their own list, so
        # the score is plain similarity and is used only to decide whether the
        # match is strong enough to offer as "this is an edition of that".
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

  # Two roads onto the form. A candidate over the similarity floor still
  # needs its name substantially present in what the file calls itself —
  # jaro noise plus a shared author put Neuromancer over the floor for
  # Pattern Recognition. And a candidate found through a series *label* is
  # offered regardless of its score, because there the score is noise in the
  # other direction: "Wayfarers, Book 1" scores ~0.24 against "The Long Way
  # to a Small, Angry Planet" while being exactly that book.
  defp offer?(candidate, hints) do
    (candidate["score"] >= @offer_local and title_evidence?(candidate, hints)) or
      series_label_evidence?(candidate, hints)
  end

  # Jaro gives ~0.5 to entirely unrelated titles, and a local book by the
  # same author collects the author's quarter-share on top — so once the
  # library held one William Gibson, Pattern Recognition offered Neuromancer
  # as "a book you already have" at 0.68, and every further import by an
  # author already on the shelf re-opened an identity question about a book
  # it plainly isn't. Similarity is not evidence of identity here; the
  # book's own name appearing in what the file calls itself is.
  #
  # And one word of it is not enough: "Elysium Fire" was offered for The
  # Consuming Fire on the strength of "fire". The book's title (or one of
  # its series names) must be *substantially* present — every word of a
  # short name, at least two of a long one — which keeps Wool findable from
  # "01 Wool" and the Wayfarers books findable through their series, and
  # keeps a single shared noun from re-opening the identity question.
  # Title evidence comes from what the file calls the BOOK — title and
  # release name, never the series tag. A series named after its first book
  # smuggled that book's whole title into this set: "Children of Memory"
  # (series-tagged "Children of Time") offered the shelved Children of Time
  # as "a book you already have". Series words belong to the series arm,
  # which has its own label and volume guards.
  defp title_evidence?(candidate, hints) do
    wanted =
      [hints.title, hints.release_title]
      |> Enum.flat_map(&Books.match_keywords/1)
      |> MapSet.new()

    substantial?(candidate["title"], wanted) or series_label_evidence?(candidate, hints)
  end

  defp series_label_evidence?(candidate, hints) do
    wanted =
      [hints.title, hints.release_title, hints.series]
      |> Enum.flat_map(&Books.match_keywords/1)
      |> MapSet.new()

    Enum.any?(
      candidate["series"] || [],
      &(substantial?(&1["name"], wanted) and series_label?(&1["name"], hints) and
          not wrong_volume?(&1, hints))
    )
  end

  # "Wayfarers, Book 4" is a label for the series' FOURTH book: the first
  # book being on the shelf is not a reason to offer it, however famous it
  # is. A label with no number, or a membership with no single number, stays
  # neutral.
  defp wrong_volume?(entry, %{series_number: number}) when not is_nil(number) do
    case single_number(entry["number"]) do
      nil -> false
      position -> not same_number?(position, number)
    end
  end

  defp wrong_volume?(_entry, _hints), do: false

  defp substantial?(name, wanted) do
    words = Books.match_keywords(name)
    shared = Enum.count(words, &MapSet.member?(wanted, &1))
    words != [] and shared >= min(2, length(words))
  end

  # A series name is only evidence when the file's label IS the series —
  # "Wayfarers, Book 1" carries no title of its own, so the series is the
  # only road to the book. When the label has its own title words ("The
  # Consuming Fire The Interdependency, Book 2"), the candidate has to match
  # on those: same-series siblings share the series name by construction,
  # and The Collapsing Empire was being offered for every later volume.
  @label_filler ~w(book books bk vol volume volumes part parts no saga series)

  defp series_label?(series_name, hints) do
    series_words = series_name |> Books.match_keywords() |> MapSet.new()

    [hints.title, hints.release_title]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn label ->
      label
      |> Books.match_keywords()
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
      # nil where the provider was never asked — switched off between the
      # registry read and the call, or missing its credentials.
      {all ++ candidates, outcomes ++ List.wrap(outcome)}
    end)
  end

  # Providers are tried in the operator's priority order, and one being down,
  # rate-limited or slow costs its results only — but the outcome is recorded
  # either way, so "this provider found nothing" and "this provider was
  # unreachable" don't look identical in the inbox.
  # **A provider that finds nothing is asked again with a plainer title.**
  # Tag titles carry things catalogue titles don't: measured on the operator's
  # own library, `"Legends and Lattes: A Novel of High Fantasy and Low Stakes"`
  # returns **nothing** from rreading-glasses while `"Legends and Lattes"`
  # returns the book — with a real publication date of 2022-02-22, where the
  # only provider that did answer knew nothing but the year. So the subtitle
  # cost the import its date, not just a candidate.
  #
  # Tried second rather than first because a subtitle is sometimes the only
  # thing telling two books apart; this widens a search that failed, which is
  # the same thing providers do internally.
  defp search_provider(entry, query, hints, opts) do
    case search_books(entry, query, opts) do
      {:ok, books} ->
        candidates =
          books |> Enum.take(@candidate_limit) |> Enum.map(&provider_candidate(&1, entry, hints))

        {candidates, Outcome.ok(entry, length(candidates))}

      {:error, reason} ->
        Logger.warning(fn ->
          "Auto-match: #{entry.id} failed for #{inspect(to_string(query))}: #{inspect(reason)}"
        end)

        {[], Outcome.from_error(entry, reason)}
    end
  end

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
  Hints from a library record's own fields — the edit forms' analog of
  `hints/1`. Same scoring, ranking provider records against what the record
  already knows instead of what the files claimed.
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
      # No files behind a form: the operator typed these fields, and a typed
      # narrator is a *stated* one, which the forward scorer already handles.
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
      # carried alongside the date because it is not derivable from it:
      # year-only knowledge arrives as a literal Jan 1st, and rendering that
      # as a real release day is the exact bug the v1.9.0 punch list fixed
      # for the import forms
      "published_format" => book.published && to_string(book.published.display_format),
      "publisher" => book.publisher,
      "cover_url" => book.cover_url,
      "description" => book.description,
      "score" => score(book.title, authors, narrators, book.asin, series, hints)
    }
  end

  # A series membership is a name AND a position, and the position was being
  # thrown away here — every provider we use reports it (Hardcover's
  # `position`/`details`, rreading-glasses' `PositionInSeries`, Audible's
  # `sequence`), and the inbox then asked the operator for a number nobody had
  # to look up. Kept as maps rather than two parallel lists so a book that is
  # #10.5 in one series and #3 in another survives the trip.
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
        # The label names a series and a number, and this candidate IS that
        # series at that number: identity, not similarity — the label was
        # never the title, so its title score is noise. Companion markers
        # still subtract.
        :match ->
          {1.0, companion_penalty(title)}

        # And a candidate at a DIFFERENT number is the wrong sibling no
        # matter how the strings score: "Wayfarers, Book 4" must not match
        # the series' famous first book.
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

    # The narrator only speaks when both sides have one. Recording-level hits
    # carry narrators and work-level hits don't, so this quietly does nothing
    # at the work level rather than needing a separate scorer — and at the
    # recording level it's decisive, because it is the only thing that
    # distinguishes two recordings of the same book.
    base
    |> apply_narrator(narrators, hints.narrator)
    |> Kernel.*(penalty)
    |> Float.round(3)
  end

  # "As You Wish: Inconceivable Tales from the Making of The Princess Bride"
  # against a file's bare "As You Wish": every subtitle word counted as
  # content the query didn't ask for, and the length penalty scored the right
  # book like a study guide (0.316, measured). A candidate whose *head* — the
  # part before a subtitle separator — IS the queried title is that title
  # written out in full, so it scores as an exact title with no length
  # penalty. The same asymmetric-containment rule the seeder's
  # `same_title?/2` applies, and asymmetric for the same reason: a shared
  # PREFIX must not match, or "The Expanse: Caliban's War" answers a search
  # for "The Expanse: Leviathan Wakes". Companion markers still subtract —
  # "As You Wish: Summary & Analysis" has the right head and is still not
  # the book.
  # In both directions, same as the seeder's `same_title?/2`: the catalogue
  # may write the subtitle out where the tags are bare (As You Wish), or the
  # tags may carry it where the catalogue is bare — "House of Earth and
  # Blood: The Crescent City, Book 1" is the dominant real-world tag shape,
  # and the record titled exactly its head IS the book the file means.
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

  # Everything before the first subtitle separator — a colon, or a dash with
  # space around it. A hyphen inside a word ("Wild-Built") is not a separator.
  defp title_head(title) when is_binary(title) do
    title |> String.split(~r/\s*:\s|\s+[-–—]\s+/u, parts: 2) |> hd()
  end

  defp title_head(other), do: other

  # Whether the file's label and this candidate's series membership answer
  # each other. Three-valued, like every "didn't say" in this module:
  #
  #   :match     the label names a series and a number, and the candidate is
  #              at that number in a series whose name the label contains
  #   :conflict  same series, single-number position, different number — the
  #              wrong sibling, whatever the strings score
  #   :unstated  no label number, no matching series entry, or a position
  #              that isn't a single number ("1-4" box sets stay neutral)
  defp series_identity(series, %{series_number: number} = hints) when not is_nil(number) do
    label_words =
      [hints.title, hints.series]
      |> Enum.flat_map(&Books.match_keywords/1)
      |> MapSet.new()

    series
    |> List.wrap()
    |> Enum.find(fn entry ->
      words = Books.match_keywords(entry["name"])
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

  # filename first — GraphicAudio names releases precisely; tag titles are
  # messier and only get a say when the name says nothing
  defp part_hint(%ReleaseName{parts_total: total} = parsed, _tag_parsed) when is_integer(total),
    do: {parsed.part_number, total}

  defp part_hint(_parsed, %ReleaseName{parts_total: total} = tag_parsed) when is_integer(total),
    do: {tag_parsed.part_number, total}

  defp part_hint(_parsed, _tag_parsed), do: nil

  # A GraphicAudio file tagged `part=1` feeds the tags' series_number field,
  # so a part-set release would claim "book N" of whatever series gets
  # proposed — for any part but the first, confidently wrong. When the
  # number agrees with the detected part number and nothing actually names a
  # series, the number is the part's, not a series position.
  defp suppress_part_polluted_series_number(nil, _part, _series), do: nil
  defp suppress_part_polluted_series_number(number, nil, _series), do: number

  defp suppress_part_polluted_series_number(number, {part_number, _total}, series) do
    if !(is_nil(series) and is_integer(part_number) and
           Decimal.compare(number, Decimal.new(part_number)) == :eq),
       do: number
  end

  defp apply_narrator(score, narrators, narrator) when narrators in [nil, []] or is_nil(narrator),
    do: score

  # Treated as a near-binary fact rather than blended in, because jaro is
  # useless here: two entirely unrelated names ("Robertson Dean" vs "Jeff
  # Harding") still score 0.53, so averaging it in left the *wrong reader's*
  # edition at 0.81 — comfortably "likely", for a recording that is simply not
  # the one in hand. Agreement is a modest boost; disagreement is decisive,
  # since at this level the narrator is what the two candidates differ by.
  defp apply_narrator(score, narrators, narrator) do
    match = narrators |> Enum.map(&similarity(&1, narrator)) |> Enum.max(fn -> 0.0 end)

    if match >= @narrator_match do
      min(score * 1.05, 1.0)
    else
      score * @narrator_mismatch
    end
  end

  # Titles that CONTAIN what we're looking for plus a pile of other words are
  # the failure mode jaro distance cannot see: "A Study Guide for William
  # Gibson's Neuromancer" and "William Gibson's Neuromancer, the Graphic
  # Novel" both scored ~0.6–0.72 against "Neuromancer" purely on shared
  # substrings, and sat in the candidate list looking plausible.
  #
  # Two penalties, because there are two different tells. A companion-work
  # marker ("study guide", "graphic novel") is decisive on its own. Sheer
  # extra length is softer evidence — subtitles and series names are
  # legitimate — so it scales rather than disqualifies.
  defp title_penalty(nil, _wanted), do: 1.0
  defp title_penalty(_title, nil), do: 1.0

  defp title_penalty(title, wanted) do
    companion_penalty(title) * length_penalty(title, wanted)
  end

  # Deliberately NOT added to `normalize/1`: stripping these words would make
  # a study guide match its subject *better*, which is the opposite of what's
  # needed. They have to subtract.
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

  # Matched with spaces removed on both sides: "Spark Notes Harry Potter…"
  # spelled the marker as two words and evaded it, and sat at 0.698 as the
  # only thing keeping the right work under the adoption bar.
  defp companion_penalty(title) do
    condensed = title |> normalize() |> String.replace(" ", "")

    if Enum.any?(@companion_markers, &String.contains?(condensed, String.replace(&1, " ", ""))),
      do: @companion_factor,
      else: 1.0
  end

  # Words in the candidate that aren't in what we asked for. A little is
  # normal (subtitles, "A Novel"); a lot means it's a different book that
  # merely mentions this one.
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

  Three-valued for the usual reason, and **by shared name token, not by jaro**.
  Jaro cannot tell a name variant from a different human — measured on the
  operator's own Martian import:

      "J.R.R. Tolkien" vs "John Ronald Reuel Tolkien"   0.573   same person
      "Daily  Books"   vs "Andy Weir"                   0.519   unrelated

  Five hundredths apart. Blended in at a quarter share, that noise put "The
  Martian: A Novel By Andy Weir | Conversation Starters" — a companion work by
  a content farm — at **0.88** against the operator's file, because a
  head-matched title scores 1.0 and even a completely wrong author adds 0.13
  on top of 0.75 of it. Sharing a name token separates the two rows above
  perfectly, and it is the same test `Ambry.Metadata.PersonSearch` already
  applies for the same reason.

  `:unstated` covers both sides being silent *and* a name that reduces to
  nothing comparable ("J.R.R."), which abstains rather than guessing.
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

  # Titles differ in punctuation and subtitle noise far more often than in
  # substance, and none of that should cost a match.
  defp normalize(string) do
    string
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
