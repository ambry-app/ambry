defmodule Ambry.Inbox.AutoMatch do
  @moduledoc """
  Proposes what an inbox item is, so confirming it can be one click.

  ## Two matches, not one

  An item needs a **work** match (which Book — title, authors, series) and a
  **recording** match (which Media — narrators, cover, chapters, release
  date). They use different keys and fail independently: an ASIN identifies a
  recording outright, title-and-author identifies a work fuzzily, and you can
  land the right work with the wrong recording — a dramatized adaptation
  instead of the standard narration — or the right recording under the wrong
  work. So each gets its own ranked candidates and its own score.

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
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  require Logger

  @candidate_limit 8

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
  def match(%InboxItem{} = item) do
    hints = hints(item)
    work = match_work(hints)

    %{
      matches: %{
        "work" => work,
        # The recording level is given the matched work, because a work's own
        # edition list is a third key alongside searching: once we know which
        # book this is, its editions are the most direct route to the
        # recordings that exist — including ones no storefront will return.
        "recording" => match_recording(hints, work),
        "hints" => stringify_hints(hints)
      }
    }
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
    key = agreement_key(best)

    candidates
    |> Enum.filter(&(agreement_key(&1) == key))
    |> Enum.take(@group_limit)
  end

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
      title: presence(tags["book_title"]) || parsed.title,
      author: first(tags["authors"]) || parsed.author,
      narrator: first(tags["narrators"]) || parsed.narrator,
      series: presence(tags["series"]) || parsed.series,
      asin: presence(tags["asin"]) || parsed.asin
    }
  end

  # Local Books are kept in their own list, not ranked among the provider
  # records. Reusing a Book you already have and importing one you don't are
  # different *outcomes* — one creates nothing, inherits the book's curation
  # and adds an alternate edition — while a provider record is *evidence*
  # about a book. Ranking them together made the form ask one question that
  # was really two.
  defp match_work(hints) do
    query = work_query(hints)

    {candidates, outcomes} = provider_books(:work, query, hints)

    query
    |> level_result(candidates, outcomes)
    |> Map.put("local", local_books(hints))
    |> hydrate_top()
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
  defp hydrate_top(%{"candidates" => candidates} = result) do
    wanted = candidates |> top_group() |> MapSet.new(&ref/1)

    %{
      result
      | "candidates" =>
          Enum.map(candidates, fn record ->
            if MapSet.member?(wanted, ref(record)), do: details(record), else: record
          end)
    }
  end

  defp hydrate_top(result), do: result

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
  def details(record) do
    case details_for(record) do
      nil -> record
      fuller -> record |> Map.merge(fuller) |> hydrated()
    end
  end

  defp details_for(%{"source" => "provider:" <> provider_id, "id" => id}) when is_binary(id) do
    case Providers.book_details(provider_id, id, []) do
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

  defp details_for(_candidate), do: nil

  # An ASIN is a recording-level key, so when there is one it *is* the query:
  # a hit on it is definitive in a way no title match ever is.
  defp match_recording(%{asin: asin} = hints, work) when is_binary(asin) do
    query = %Provider.Query{keywords: asin}
    {candidates, outcomes} = provider_books(:recording, query, hints)
    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints)

    level_result(query, candidates ++ editions, outcomes ++ edition_outcomes)
  end

  # Structured, not concatenated. Audible's catalog matches `title` against
  # the title alone, so the old `"#{title} #{author}"` string searched for a
  # book literally called that and returned nothing — the recording level came
  # up empty on every single item. The narrator goes in too: it is the field
  # that tells two recordings of one work apart.
  defp match_recording(hints, work) do
    query = %Provider.Query{
      title: hints.title,
      author: hints.author,
      narrator: hints.narrator
    }

    {candidates, outcomes} = provider_books(:recording, query, hints)
    {editions, edition_outcomes} = editions_for(top_group(work["candidates"]), hints)

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
  def editions_for(records, hints) do
    records
    |> Enum.filter(&editions_capable?/1)
    |> Enum.reduce({[], []}, fn record, {candidates, outcomes} ->
      "provider:" <> provider_id = record["source"]
      {found, outcome} = fetch_editions(provider_id, record["id"], hints, work_ref(record))
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

  defp fetch_editions(provider_id, work_id, hints, of_work) do
    case Providers.editions(provider_id, work_id, []) do
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
  defp agreement_key(%{"narrators" => narrators} = candidate) when narrators not in [nil, []] do
    {:recording, normalize(candidate["title"] || ""),
     Enum.sort(Enum.map(narrators, &normalize/1)), candidate["asin"]}
  end

  defp agreement_key(candidate) do
    {:work, normalize(candidate["title"] || ""),
     candidate["authors"] |> List.wrap() |> Enum.map(&normalize/1) |> Enum.sort()}
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
  defp confidence(candidates) do
    candidates
    |> Enum.group_by(&agreement_key/1)
    |> Map.values()
    |> Enum.map(&group_score/1)
    |> Enum.sort(:desc)
    |> decide()
  end

  defp group_score(group) do
    best = group |> Enum.map(&(&1["score"] || 0.0)) |> Enum.max()
    bonus = if length(group) > 1, do: @agreement_bonus, else: 0.0

    min(best + bonus, 1.0)
  end

  defp decide([]), do: 0.0
  defp decide([only]), do: only

  defp decide([best, second | _rest]) do
    penalty = 0.5 * second / max(best, 0.001)

    (best * (1.0 - penalty))
    |> max(0.0)
    |> min(best)
    |> Float.round(3)
  end

  defp local_books(%{title: nil}), do: []

  defp local_books(hints) do
    query = to_string(%Provider.Query{title: hints.title, author: hints.author})

    {books, _more} = Books.list_books(0, @candidate_limit, %{search: query})

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
  end

  defp provider_books(_level, nil, _hints), do: {[], []}

  defp provider_books(level, query, hints) do
    [level: level, capability: :book_search]
    |> Registry.enabled()
    |> Enum.map(&search_provider(&1, query, hints))
    |> Enum.reduce({[], []}, fn {candidates, outcome}, {all, outcomes} ->
      {all ++ candidates, outcomes ++ [outcome]}
    end)
  end

  # Providers are tried in the operator's priority order, and one being down,
  # rate-limited or slow costs its results only — but the outcome is recorded
  # either way, so "this provider found nothing" and "this provider was
  # unreachable" don't look identical in the inbox.
  defp search_provider(entry, query, hints) do
    case Providers.search_books(entry.id, query, []) do
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

  defp presence(nil), do: nil
  defp presence(string) when is_binary(string), do: with("" <- String.trim(string), do: nil)
  defp presence(_other), do: nil
end
