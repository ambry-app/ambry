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

  ## Local records outrank providers

  A work already in the library is the best possible match: it's what stops a
  second recording of a book from creating a duplicate Book. So local hits
  are ranked ahead of provider results at equal confidence.
  """

  alias Ambry.Books
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Providers
  alias Ambry.Metadata.Registry

  require Logger

  @candidate_limit 8

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

    %{
      matches: %{
        "work" => match_work(hints),
        "recording" => match_recording(hints),
        "hints" => stringify_hints(hints)
      }
    }
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

  defp match_work(hints) do
    query = work_query(hints)

    {candidates, outcomes} = provider_books(:work, query, hints)

    level_result(query, local_books(hints) ++ candidates, outcomes)
  end

  # An ASIN is a recording-level key, so when there is one it *is* the query:
  # a hit on it is definitive in a way no title match ever is.
  defp match_recording(%{asin: asin} = hints) when is_binary(asin) do
    query = %Provider.Query{keywords: asin}
    {candidates, outcomes} = provider_books(:recording, query, hints)

    level_result(query, candidates, outcomes)
  end

  # Structured, not concatenated. Audible's catalog matches `title` against
  # the title alone, so the old `"#{title} #{author}"` string searched for a
  # book literally called that and returned nothing — the recording level came
  # up empty on every single item. The narrator goes in too: it is the field
  # that tells two recordings of one work apart.
  defp match_recording(hints) do
    query = %Provider.Query{
      title: hints.title,
      author: hints.author,
      narrator: hints.narrator
    }

    {candidates, outcomes} = provider_books(:recording, query, hints)

    level_result(query, candidates, outcomes)
  end

  defp work_query(%{title: nil}), do: nil

  defp work_query(hints), do: %Provider.Query{title: hints.title, author: hints.author}

  defp level_result(query, candidates, outcomes) do
    candidates =
      candidates
      |> merge_agreeing()
      |> Enum.sort_by(& &1["score"], :desc)
      |> Enum.take(@candidate_limit)

    %{
      "query" => query && to_string(query),
      "candidates" => candidates,
      # the operator confirms; this is only the suggestion
      "selected" => candidates |> List.first() |> selected_ref(),
      "confidence" => confidence(candidates),
      # which providers were asked, and what each said. A provider that fails
      # used to vanish silently, leaving the operator to wonder why a source
      # they had enabled contributed nothing.
      "providers" => outcomes
    }
  end

  defp selected_ref(nil), do: nil
  defp selected_ref(candidate), do: %{"source" => candidate["source"], "id" => candidate["id"]}

  # Two providers returning the same work is the strongest signal available,
  # not a disagreement — but the runner-up penalty below read it as one and
  # dropped a perfect double hit to 0.5 confidence, which is why so many
  # obviously-right matches asked to be looked at. Duplicates collapse into
  # one candidate that remembers it was corroborated.
  defp merge_agreeing(candidates) do
    candidates
    |> Enum.group_by(&agreement_key/1)
    |> Enum.map(fn {_key, [first | rest]} ->
      case rest do
        [] ->
          first

        _corroborated ->
          first
          |> Map.put("also_from", Enum.map(rest, &(&1["provider_name"] || &1["source"])))
          |> Map.put("score", min(first["score"] + @agreement_bonus, 1.0))
      end
    end)
  end

  # A local record and a provider hit for the same work are deliberately NOT
  # merged: "reuse the book you already have" and "create it from this
  # provider" are different outcomes, and the operator has to be able to see
  # both. Only provider-to-provider duplicates collapse.
  defp agreement_key(%{"source" => "local", "id" => id}), do: {:local, id}

  defp agreement_key(candidate) do
    {:work, normalize(candidate["title"] || ""),
     candidate["authors"] |> List.wrap() |> Enum.map(&normalize/1) |> Enum.sort()}
  end

  # Confidence is about the *decision*, not just the top hit: a strong match
  # with a genuinely different runner-up is exactly the case a human should
  # look at, so a close second pulls it down.
  defp confidence([]), do: 0.0

  defp confidence([best]), do: best["score"]

  defp confidence([best, second | _rest]) do
    penalty = 0.5 * second["score"] / max(best["score"], 0.001)

    (best["score"] * (1.0 - penalty))
    |> max(0.0)
    |> min(best["score"])
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
        "series" => Enum.map(book.series || [], & &1.name),
        "published" => book.published && Date.to_iso8601(book.published),
        # a work already in the library beats an equally-good provider hit:
        # reusing it is what prevents duplicate Books
        "score" =>
          score(book.title, Enum.map(book.authors || [], & &1.name), nil, nil, hints) + 0.05
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
      "series" => Enum.map(book.series || [], & &1.name),
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
