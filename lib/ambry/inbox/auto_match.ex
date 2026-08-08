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
  approves, and approval is what creates records.

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

  @doc """
  Builds work and recording proposals for an item.

  Returns the attrs to store; never raises, and degrades to whatever it could
  find — a provider being down means fewer candidates, not a failed item.
  """
  def match(%InboxItem{} = item, opts \\ []) do
    hints = hints(item)
    work = match_work(hints, opts)

    # The recording level is given the matched work, because a work's own
    # edition list is a third key alongside searching: once we know which book
    # this is, its editions are the most direct route to the recordings that
    # exist — including ones no storefront will return.
    recording = match_recording(hints, work, opts)

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
  def person_key(name) when is_binary(name),
    do: name |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.trim()

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
    Enum.reduce(PersonSearch.providers(), {[], []}, fn entry, {candidates, outcomes} ->
      {matches, outcome} = PersonSearch.matches_with_outcome(entry, name, opts)
      {candidates ++ Enum.map(matches, &person_candidate/1), outcomes ++ [outcome]}
    end)
  end

  defp person_candidate(%PersonSearch.Match{} = match) do
    %{
      "source" => "provider:#{match.provider_id}",
      "provider_name" => match.provider_name,
      "id" => to_string(match.id),
      "name" => match.name,
      "description" => presence(match.description),
      # what tells two same-named humans apart in a grid — TMDB's known-for
      # credits, mostly
      "note" => presence(match.note),
      "images" => match.images
    }
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

  def top_group([best | _rest] = candidates) do
    candidates
    |> Enum.filter(&agrees?(&1, best))
    |> Enum.take(@group_limit)
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
      asin: presence(tags["asin"]) || parsed.asin,
      # Kept **beside** `title` rather than folded into it. The tags win the
      # hint because they are the more reliable field, but the name is a real
      # second opinion and the form has to be able to offer it — measured on
      # the operator's library, the two disagree on 105 of 198 releases, and
      # neither is reliably the better one. `title` is what gets searched and
      # scored; this is what gets proposed.
      release_title: parsed.title
    }
  end

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
    |> level_result(candidates, outcomes)
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

    %{
      result
      | "candidates" =>
          Enum.map(candidates, fn record ->
            if MapSet.member?(wanted, ref(record)), do: details(record, opts), else: record
          end)
    }
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
    case details_for(record, opts) do
      nil -> record
      fuller -> record |> Map.merge(fuller) |> hydrated()
    end
  end

  defp details_for(%{"source" => "provider:" <> provider_id, "id" => id}, opts)
       when is_binary(id) do
    case Providers.book_details(provider_id, id, opts) do
      {:ok, book} ->
        # Only fields the summary can be *missing*. The title, authors and
        # score stay as matched — re-deriving them here would silently move
        # what the operator already saw ranked.
        %{
          "description" => presence(book.description),
          "cover_url" => presence(book.cover_url),
          "publisher" => presence(book.publisher),
          "series" => series_refs(book.series)
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
        |> Map.new()

      {:error, reason} ->
        # Never fatal: the summary is still a usable candidate, and an item
        # that matched shouldn't fail because one enrichment call didn't.
        Logger.warning(fn ->
          "Auto-match: details for #{provider_id}/#{id}: #{inspect(reason)}"
        end)

        nil
    end
  end

  defp details_for(_candidate, _opts), do: nil

  # An ASIN is a recording-level key, so when there is one it *is* the query:
  # a hit on it is definitive in a way no title match ever is.
  defp match_recording(%{asin: asin} = hints, work, opts) when is_binary(asin) do
    query = %Provider.Query{keywords: asin}
    {candidates, outcomes} = provider_books(:recording, query, hints, opts)
    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints, opts)

    level_result(query, candidates ++ editions, outcomes ++ edition_outcomes)
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

    level_result(query, candidates ++ editions, outcomes ++ edition_outcomes)
  end

  @doc """
  The recordings the given work records are known to have.

  This is what finds an edition a storefront has erased: Audible's catalog API
  is a storefront, not a bibliography — when rights lapse and a title is
  pulled, it vanishes from search *and* from direct ASIN lookup, with no record
  that it ever existed. Hardcover and rreading-glasses are databases of
  editions rather than shops, so they still have it. Measured for Neuromancer:
  Audible 1 audio edition, Hardcover 7 — including a narrator Audible doesn't
  list at all.

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
    records
    |> Enum.filter(&editions_capable?/1)
    |> Enum.reduce({[], []}, fn record, {candidates, outcomes} ->
      "provider:" <> provider_id = record["source"]
      {found, outcome} = fetch_editions(provider_id, record["id"], hints, work_ref(record), opts)
      {candidates ++ found, outcomes ++ outcome}
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

        {candidates,
         [
           %{
             "id" => "#{provider_id}:editions",
             "name" => "#{entry.display_name} editions",
             "status" => "ok",
             "count" => length(candidates)
           }
         ]}

      {:error, reason} ->
        Logger.warning(fn -> "Auto-match: editions for #{provider_id}: #{inspect(reason)}" end)

        {[],
         [
           %{
             "id" => "#{provider_id}:editions",
             "name" => "#{provider_name(provider_id)} editions",
             "status" => "failed",
             "count" => 0,
             "reason" => describe(reason)
           }
         ]}
    end
  end

  defp provider_name(provider_id) do
    case Registry.fetch(provider_id) do
      {:ok, entry} -> entry.display_name
      _unknown -> provider_id
    end
  end

  defp work_query(%{title: nil}), do: nil

  defp work_query(hints), do: %Provider.Query{title: hints.title, author: hints.author}

  defp level_result(query, candidates, outcomes) do
    %{
      "query" => query && to_string(query),
      # The flattened string is what the cache keys on and what text-only
      # providers see, but it isn't what was *asked* — the fields are, and
      # they're what the operator needs to read when a match looks wrong.
      "query_fields" => query_fields(query),
      "candidates" => rank(candidates),
      "confidence" => confidence(candidates),
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
    candidates
    |> Enum.sort_by(& &1["score"], :desc)
    |> Enum.take(@candidate_limit)
  end

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
    normalize(one["title"] || "") == normalize(other["title"] || "") and
      compatible?(one["narrators"], other["narrators"]) and
      compatible?(one["authors"], other["authors"])
  end

  defp compatible?(one, other) do
    case {name_set(one), name_set(other)} do
      {[], _unstated} -> true
      {_unstated, []} -> true
      {one, other} -> one == other
    end
  end

  defp name_set(names), do: names |> List.wrap() |> Enum.map(&normalize/1) |> Enum.sort()

  # Confidence is about the *decision*, not just the top hit: a strong match
  # with a genuinely different runner-up is exactly the case a human should
  # look at, so a close second pulls it down.
  #
  # Corroboration is not a rival. Records are no longer fused, so two providers
  # returning the same work are two rows — and scoring them as rivals would
  # read the best-corroborated match in the library as the most doubtful one,
  # which is the bug #1186 fixed by merging. Grouping for the score keeps that
  # fix without the merge.
  defp confidence(candidates) do
    candidates
    |> group_agreeing()
    |> Enum.map(fn [held | _rest] = group -> {group_score(group), held} end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> decide()
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

  defp decide([]), do: 0.0
  defp decide([{only, _held}]), do: only

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
  defp decide([{best, best_held}, {second, second_held} | _rest]) do
    gap = best - second

    penalty =
      if gap >= @decisive,
        do: 0.0,
        else: 0.5 * (1.0 - :math.pow(gap / @decisive, 2))

    penalty =
      if rival?(best, best_held, second_held),
        do: penalty,
        else: penalty * @sibling_discount

    (best * (1.0 - penalty))
    |> max(0.0)
    |> min(best)
    |> Float.round(3)
  end

  defp rival?(best_score, best_held, second_held) do
    best_score < @settled_score or
      confusable?(best_held["title"], second_held["title"])
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
        "score" => score(book.title, Enum.map(book.authors || [], & &1.name), nil, nil, hints)
      }
    end)
    |> Enum.filter(&(&1["score"] >= @offer_local))
    |> Enum.sort_by(& &1["score"], :desc)
  end

  defp provider_books(_level, nil, _hints, _opts), do: {[], []}

  defp provider_books(level, query, hints, opts) do
    [level: level, capability: :book_search]
    |> Registry.enabled()
    |> Enum.map(&search_provider(&1, query, hints, opts))
    |> Enum.reduce({[], []}, fn {candidates, outcome}, {all, outcomes} ->
      {all ++ candidates, outcomes ++ [outcome]}
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

        {candidates,
         %{
           "id" => entry.id,
           "name" => entry.display_name,
           "status" => "ok",
           "count" => length(candidates)
         }}

      {:error, reason} ->
        Logger.warning(fn ->
          "Auto-match: #{entry.id} failed for #{inspect(to_string(query))}: #{inspect(reason)}"
        end)

        {[],
         %{
           "id" => entry.id,
           "name" => entry.display_name,
           "status" => "failed",
           "count" => 0,
           "reason" => describe(reason)
         }}
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

  # Enough for the operator to tell a rate limit from a bad token from an
  # instance being down, without leaking a whole HTTP response into jsonb.
  defp describe(reason) do
    reason |> inspect() |> String.slice(0, 200)
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

    %{
      "source" => "provider:#{entry.id}",
      "provider_name" => entry.display_name,
      "id" => book.id,
      "asin" => book.asin,
      "title" => book.title,
      "authors" => authors,
      "narrators" => narrators,
      "series" => series_refs(book.series),
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
      "score" => score(book.title, authors, narrators, book.asin, hints)
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
  defp score(_title, _authors, _narrators, asin, %{asin: asin}) when is_binary(asin), do: 1.0

  defp score(title, authors, narrators, _asin, hints) do
    base =
      case author_similarity(authors, hints.author) do
        nil -> similarity(title, hints.title)
        author_score -> similarity(title, hints.title) * 0.75 + author_score * 0.25
      end

    # The narrator only speaks when both sides have one. Recording-level hits
    # carry narrators and work-level hits don't, so this quietly does nothing
    # at the work level rather than needing a separate scorer — and at the
    # recording level it's decisive, because it is the only thing that
    # distinguishes two recordings of the same book.
    base
    |> apply_narrator(narrators, hints.narrator)
    |> Kernel.*(title_penalty(title, hints.title))
    |> Float.round(3)
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

  defp companion_penalty(title) do
    normalized = normalize(title)

    if Enum.any?(@companion_markers, &String.contains?(normalized, &1)),
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

  defp author_similarity(_authors, nil), do: nil
  defp author_similarity([], _author), do: 0.0

  defp author_similarity(authors, author) do
    authors |> Enum.map(&similarity(&1, author)) |> Enum.max(fn -> 0.0 end)
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
