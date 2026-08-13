defmodule Ambry.Inbox.Lookup do
  @moduledoc """
  Asking providers things *after* an item has been matched.

  Matching is thorough and runs on a serial, retrying queue, so most items
  never need any of this. It exists for the case the operator's own words
  describe: **"you got this wrong"** — where the right answer wasn't in the
  list at all, or a provider was rate-limited during the scan, or a record
  nobody expected to matter turns out to be the one.

  Everything here writes to `inbox_items.matches`, which is *evidence*, and
  never to the draft, which is *decisions*. That's the same boundary
  discovery respects, and it's what lets a re-search add records without
  disturbing a curated choice: new records simply appear un-ticked.

  Records are added, never replaced. A record the draft already points at
  keeps its identity across a re-search — otherwise re-searching would
  silently un-tick whatever the operator had chosen.

  The provider fan-out itself lives in `Ambry.Metadata.Search` — it was never
  inbox-specific, and the legacy admin forms converge on it. What stays here
  is what IS inbox-specific: normalizing hits against the item's hints
  (scoring), and writing evidence into `inbox_items.matches`.
  """
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.InboxItem
  alias Ambry.Metadata.Outcome
  alias Ambry.Metadata.Provider
  alias Ambry.Metadata.Registry
  alias Ambry.Metadata.Search
  alias Ambry.Repo

  @doc """
  Fetches the full record behind a thin search hit.

  Matching hydrates the records about the top work; anything further down the
  list stays a summary until somebody says it matters. A summary can be
  missing the description and the cover entirely — measured against
  rreading-glasses, search returns a work with one edition and details returns
  the same work with seventeen.
  """
  def hydrate(%InboxItem{} = item, level, record_ref) do
    {records, failures} =
      item
      |> records(level)
      |> Enum.map_reduce([], fn record, failures ->
        if AutoMatch.ref(record) == record_ref and !record["hydrated"] do
          case AutoMatch.details_with_outcome(record) do
            {record, nil} -> {record, failures}
            {record, outcome} -> {record, failures ++ [outcome]}
          end
        else
          {record, failures}
        end
      end)

    item
    |> update_records(level, fn _existing -> records end)
    |> update_outcomes(level, failures)
  end

  @doc """
  Asks every editions-capable database what recordings the given work records
  have.

  This is the route to an edition no storefront will admit exists. Audible's
  catalog is a shop: when rights lapse the title vanishes from search and from
  ASIN lookup alike. Hardcover is a database of editions and keeps it —
  measured, R.C. Bray's delisted Martian is there with its ASIN and Audible
  has only the Wil Wheaton re-recording.

  **Hardcover, and only Hardcover.** rreading-glasses is named here in older
  notes and does not belong: its edition list never carries a narrator (the
  Goodreads query it issues omits secondary contributors entirely), which
  makes it useless at the level where the narrator is the whole question.
  """
  def editions(%InboxItem{} = item, work_refs) do
    records =
      item
      |> records("work")
      |> Enum.filter(&(AutoMatch.ref(&1) in work_refs))

    hints = AutoMatch.hints(item)
    {found, outcomes} = AutoMatch.editions_for(records, hints)

    item
    |> update_records("recording", &(&1 |> add(found) |> refine(item, "recording", hints)))
    |> update_outcomes("recording", outcomes)
  end

  @doc """
  Runs a search the operator wrote, and adds whatever it returns.

  The last resort in the ranked-candidates design: the stored list makes
  "show me the alternatives" free, and this is for the case it's actually
  for — the right answer isn't in the list at all, usually because the tags
  sent the search somewhere strange.
  """
  def research(%InboxItem{} = item, level, fields) do
    query = query_from(fields)

    if Provider.Query.blank?(query) do
      {:ok, item}
    else
      hints = AutoMatch.hints(item)
      {found, outcomes} = search(level, query, hints)

      item
      |> update_records(level, &(&1 |> add(found) |> refine(item, level, hints)))
      |> update_outcomes(level, outcomes)
      |> remember_query(level, query)
    end
  end

  @doc """
  Asks one provider again — the one that was rate-limited or down when this
  item was matched.

  Without this, a 429 during a scan costs an item that provider's records
  until somebody re-runs the whole match. The "couldn't be reached" chip is
  the retry button.

  **The chip carries what kind of call failed, and this has to honour it.**
  A provider is asked three different things about one item — a search, the
  details behind its hits, the editions of the work it named — and they fail
  independently. Re-running the search when what failed was a details call
  would report success having fixed nothing, which is how the `:editions`
  chip came to be a button that did nothing at all: its id
  (`hardcover:editions`) is not a registry id, so the lookup missed, and the
  clause below returned the item untouched without a word.
  """
  def retry_provider(%InboxItem{} = item, level, outcome_id) do
    {provider_id, kind} = Outcome.split(outcome_id)

    case Registry.fetch(provider_id) do
      {:ok, entry} -> retry(item, level, entry, kind)
      {:error, reason} -> {:error, reason}
    end
  end

  defp retry(item, level, entry, :search) do
    hints = AutoMatch.hints(item)
    query = stored_query(item, level) || query_from(%{})
    {books, outcome} = Search.books_one(entry, query)
    found = AutoMatch.records_from(books, entry, hints)

    item
    |> update_records(level, &(&1 |> add(found) |> refine(item, level, hints)))
    |> update_outcomes(level, [outcome])
  end

  # Every record of this provider's that matching meant to hydrate, not just
  # one: they all feed the field candidates, so a retry that fixed the top
  # record and left its siblings thin would clear the chip while the evidence
  # it was warning about was still missing.
  defp retry(item, level, entry, :details) do
    source = "provider:#{entry.id}"

    {records, outcomes} =
      item
      |> records(level)
      |> Enum.map_reduce([], fn record, outcomes ->
        if record["source"] == source and !record["hydrated"] do
          case AutoMatch.details_with_outcome(record, refresh: true) do
            {record, nil} -> {record, outcomes}
            {record, outcome} -> {record, outcomes ++ [outcome]}
          end
        else
          {record, outcomes}
        end
      end)

    item
    |> update_records(level, fn _existing -> records end)
    |> update_outcomes(level, AutoMatch.tally_outcomes(outcomes))
  end

  # Editions hang off the work records, whatever level the chip was rendered
  # at — the recording level is where they land, and the work level is where
  # they came from.
  defp retry(item, level, entry, :editions) do
    hints = AutoMatch.hints(item)

    records =
      item
      |> records("work")
      |> Enum.filter(&(&1["source"] == "provider:#{entry.id}"))
      |> AutoMatch.top_group()

    {found, outcomes} = AutoMatch.editions_for(records, hints, refresh: true)

    item
    |> update_records(level, &(&1 |> add(found) |> refine(item, level, hints)))
    |> update_outcomes(level, outcomes)
  end

  defp retry(item, _level, _entry, _kind), do: {:ok, item}

  @doc """
  Asks every person-capable database about one human again.

  Matching already searched everybody the credits named, so this is for the
  case the name has *changed* since — the operator renamed a credit, revealed
  a pen name, or split one person into two — where the key has no evidence
  behind it because nobody had heard of that name when the item was matched.

  Writes into `matches["people"][key]` exactly as matching does, so the
  person's photo and bio fields pick the results up on the next reseed. The
  same rule as everywhere else here: **evidence is added, never replaced**, so
  a re-search cannot un-choose a photo the operator already picked.
  """
  def research_person(%InboxItem{} = item, key, name) do
    case String.trim(name || "") do
      "" ->
        {:ok, item}

      name ->
        {matches, outcomes} = Search.people(name)
        found = Enum.map(matches, &AutoMatch.person_candidate(&1, name))
        update_person(item, key, name, found, outcomes)
    end
  end

  defp update_person(%InboxItem{} = item, key, name, found, outcomes) do
    matches = item.matches || %{}
    people = Map.get(matches, "people") || %{}
    held = Map.get(people, key) || %{"name" => name, "roles" => [], "local" => []}

    known = MapSet.new(Map.get(held, "candidates", []) || [], &AutoMatch.ref/1)

    updated =
      held
      |> Map.put("name", name)
      |> Map.put(
        "candidates",
        AutoMatch.rank_people(
          (Map.get(held, "candidates", []) || []) ++
            Enum.reject(found, &MapSet.member?(known, AutoMatch.ref(&1))),
          name
        )
      )
      |> Map.put("providers", outcomes)

    item
    |> InboxItem.changeset(%{
      matches: Map.put(matches, "people", Map.put(people, key, updated))
    })
    |> Repo.update()
  end

  ## plumbing

  # The fan-out is Metadata.Search's; scoring the hits against this item's
  # hints is ours.
  defp search(level, query, hints) do
    {found, outcomes} = Search.books(query, level: level_atom(level))

    records =
      Enum.flat_map(found, fn {entry, books} -> AutoMatch.records_from(books, entry, hints) end)

    {records, outcomes}
  end

  # Both passes are facts about the *whole* list rather than about one record
  # — it takes a rival naming somebody the file mentions to make a candidate's
  # silence damning, and it takes another row to make a row a duplicate — so
  # they re-run over the merged list, not over the records this search
  # happened to add. Otherwise a re-search that finally turned up the right
  # reader would leave the wrong one sitting at the top on its original score.
  #
  # Order matters: collapse first, so the evidence pass scores each recording
  # once, then sort, because both passes move records around.
  defp refine(records, item, level, hints) do
    records
    |> dedupe(item, level)
    |> reweigh(level, hints)
    |> AutoMatch.order_candidates()
  end

  defp dedupe(records, item, "recording"),
    do: AutoMatch.dedupe_records(records, ticked(item, :recording, records))

  defp dedupe(records, _item, _level), do: records

  defp reweigh(records, "recording", hints), do: AutoMatch.apply_narrator_evidence(records, hints)

  defp reweigh(records, _level, _hints), do: records

  # A record the operator has ticked keeps its identity no matter what: the
  # draft points at it by ref, and collapsing it into a look-alike would break
  # that pointer — the one thing evidence-writing must never do.
  defp ticked(%InboxItem{draft: nil}, _level, _records), do: MapSet.new()

  defp ticked(%InboxItem{draft: draft}, level, records) do
    records
    |> Enum.filter(&Draft.Edit.uses?(draft, level, &1))
    |> MapSet.new(&AutoMatch.ref/1)
  end

  # New records join the list; ones already there keep their place and their
  # payload. Replacing them would un-tick the operator's choices, and keeping
  # them *first* is what lets `dedupe_records/2` collapse a look-alike into
  # the record already on the item rather than the other way round.
  defp add(existing, found) do
    known = MapSet.new(existing, &AutoMatch.ref/1)

    existing ++ Enum.reject(found, &MapSet.member?(known, AutoMatch.ref(&1)))
  end

  defp update_records(item, level, fun) do
    matches = item.matches || %{}
    level_map = Map.get(matches, level, %{})
    updated = Map.put(level_map, "candidates", fun.(Map.get(level_map, "candidates", []) || []))

    item
    |> InboxItem.changeset(%{matches: Map.put(matches, level, updated)})
    |> Repo.update()
  end

  defp update_outcomes({:ok, item}, level, outcomes), do: update_outcomes(item, level, outcomes)
  defp update_outcomes({:error, _reason} = error, _level, _outcomes), do: error

  defp update_outcomes(%InboxItem{} = item, level, outcomes) do
    matches = item.matches || %{}
    level_map = Map.get(matches, level, %{})
    existing = Map.get(level_map, "providers", []) || []

    # An outcome replaces the earlier one for the same provider: "couldn't be
    # reached" must stop saying that once it has been reached.
    fresh = MapSet.new(outcomes, & &1["id"])
    kept = Enum.reject(existing, &MapSet.member?(fresh, &1["id"]))

    updated = Map.put(level_map, "providers", kept ++ outcomes)

    item
    |> InboxItem.changeset(%{matches: Map.put(matches, level, updated)})
    |> Repo.update()
  end

  defp remember_query({:ok, item}, level, query), do: remember_query(item, level, query)
  defp remember_query({:error, _reason} = error, _level, _query), do: error

  defp remember_query(%InboxItem{} = item, level, query) do
    matches = item.matches || %{}

    updated =
      matches
      |> Map.get(level, %{})
      |> Map.put("query", to_string(query))
      |> Map.put("query_fields", Provider.Query.non_blank_fields(query))

    item
    |> InboxItem.changeset(%{matches: Map.put(matches, level, updated)})
    |> Repo.update()
  end

  defp query_from(fields), do: Provider.Query.from_fields(fields)

  defp stored_query(%InboxItem{matches: matches}, level) when is_map(matches) do
    case get_in(matches, [level, "query_fields"]) do
      fields when is_map(fields) and map_size(fields) > 0 -> query_from(fields)
      _none -> nil
    end
  end

  defp stored_query(_item, _level), do: nil

  defp records(%InboxItem{matches: matches}, level) when is_map(matches),
    do: get_in(matches, [level, "candidates"]) || []

  defp records(_item, _level), do: []

  defp level_atom("work"), do: :work
  defp level_atom("recording"), do: :recording
end
