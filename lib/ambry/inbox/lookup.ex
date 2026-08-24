defmodule Ambry.Inbox.Lookup do
  @moduledoc """
  Asking providers things *after* an item has been matched.

  Matching is thorough and runs on a serial, retrying queue, so most items
  never need any of this. It exists for the case where matching got it wrong:
  the right answer was not in the list, a provider was rate-limited during the
  scan, or a record nobody expected to matter turns out to be the one.

  Everything here writes to `inbox_items.matches`, which is *evidence*, never
  to the draft, which is *decisions*: a re-search adds records without
  disturbing a curated choice, and they appear un-ticked.

  Records are added, never replaced, keeping their identity across a
  re-search, or re-searching would silently un-tick whatever was chosen.

  The provider fan-out lives in `Ambry.Metadata.Search`; what stays here is
  inbox-specific: scoring hits against the item's hints, and writing evidence.
  """
  import Ecto.Query

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

  Matching hydrates the records about the top work; anything further down
  stays a summary until somebody says it matters. A summary can be missing
  the description, the cover and most of the edition list.
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

    hydrated = Enum.find(records, &(AutoMatch.ref(&1) == record_ref))

    item
    # By reference rather than wholesale: a search that finished while the
    # provider was being asked has records this never saw.
    |> update_records(level, fn existing ->
      Enum.map(existing, fn record ->
        if hydrated && AutoMatch.ref(record) == record_ref, do: hydrated, else: record
      end)
    end)
    |> update_outcomes(level, failures)
  end

  @doc """
  Asks every editions-capable database what recordings the given work records
  have.

  The route to an edition no storefront will admit exists: when rights lapse
  the title vanishes from search and ASIN lookup alike, while a database of
  editions keeps it.

  Only a provider whose edition list carries narrators is useful here.
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

  For the case the stored candidate list cannot cover: the right answer isn't
  in it at all, usually because the tags sent the search somewhere strange.
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

  Without this, a rate limit during a scan costs an item that provider's
  records until somebody re-runs the whole match.

  The chip carries what kind of call failed and this has to honour it: a
  provider is asked three things about one item and they fail independently.
  A kind-qualified id is also not a registry id.
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
    |> update_outcomes(level, List.wrap(outcome), clear: Outcome.id(entry.id, :search))
  end

  # Every record of this provider's that matching meant to hydrate, since
  # they all feed the field candidates: a retry that fixed only the top one
  # would clear the chip with the evidence still missing.
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
    |> update_outcomes(level, AutoMatch.tally_outcomes(outcomes),
      clear: Outcome.id(entry.id, :details)
    )
  end

  # Editions hang off the work records whatever level the chip was rendered
  # at: the recording level is where they land.
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
    |> update_outcomes(level, outcomes, clear: Outcome.id(entry.id, :editions))
  end

  defp retry(item, _level, _entry, _kind), do: {:ok, item}

  @doc """
  Asks every person-capable database about one human again.

  Matching already searched everybody the credits named, so this is for a
  name that has changed since.

  Writes into `matches["people"][key]` exactly as matching does. Evidence is
  added, never replaced, so this cannot un-choose a photo the operator picked;
  what changes is the ranking.

  The library is asked again too: "already in your library" is an answer about
  a name, and after a rename the held one is about somebody else.
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
    update_matches(item, &merge_person(&1, key, name, found, outcomes))
  end

  defp merge_person(matches, key, name, found, outcomes) do
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
      |> Map.put("local", AutoMatch.local_people(name))
      |> Map.put("providers", outcomes)

    Map.put(matches, "people", Map.put(people, key, updated))
  end

  # Read, change and write the row as committed, because several of these run
  # at once: `matches` is one jsonb column holding every level's records and
  # every person's, and the form searches for as many people as the operator
  # likes without waiting.
  #
  # Same shape as `Ambry.Inbox.update_draft_with/2` and `Importer.claim/1`.
  defp update_matches(%InboxItem{id: id}, fun) do
    Repo.transact(fn ->
      item =
        InboxItem
        |> where([i], i.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      changeset = InboxItem.changeset(item, %{matches: fun.(item.matches || %{})})

      if InboxItem.unchanged?(changeset),
        do: {:ok, item},
        else: changeset |> InboxItem.versioned() |> Repo.update()
    end)
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

  # Both passes are facts about the whole list rather than one record: it
  # takes a rival to make a candidate's silence damning, and another row to
  # make a row a duplicate. Collapse first, so the evidence pass scores each
  # recording once, then sort.
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
  # draft points at it by ref, and collapsing it would break that pointer.
  defp ticked(%InboxItem{draft: nil}, _level, _records), do: MapSet.new()

  defp ticked(%InboxItem{draft: draft}, level, records) do
    records
    |> Enum.filter(&Draft.Edit.uses?(draft, level, &1))
    |> MapSet.new(&AutoMatch.ref/1)
  end

  # New records join the list; ones already there keep their place and their
  # payload. Keeping them first is what lets `dedupe_records/2` collapse a
  # look-alike into the record already on the item.
  defp add(existing, found) do
    known = MapSet.new(existing, &AutoMatch.ref/1)

    existing ++ Enum.reject(found, &MapSet.member?(known, AutoMatch.ref(&1)))
  end

  defp update_records(item, level, fun) do
    update_matches(item, fn matches ->
      level_map = Map.get(matches, level, %{})
      updated = Map.put(level_map, "candidates", fun.(Map.get(level_map, "candidates", []) || []))
      Map.put(matches, level, updated)
    end)
  end

  defp update_outcomes(item_or_result, level, outcomes, opts \\ [])

  defp update_outcomes({:ok, item}, level, outcomes, opts),
    do: update_outcomes(item, level, outcomes, opts)

  defp update_outcomes({:error, _reason} = error, _level, _outcomes, _opts), do: error

  defp update_outcomes(%InboxItem{} = item, level, outcomes, opts) do
    update_matches(item, fn matches ->
      update_outcomes_in(matches, level, outcomes, opts)
    end)
  end

  defp update_outcomes_in(matches, level, outcomes, opts) do
    level_map = Map.get(matches, level, %{})
    existing = Map.get(level_map, "providers", []) || []

    # An outcome replaces the earlier one for the same provider.
    #
    # `:clear` is for a retry that comes back with nothing to report, where
    # the provider implements no such call: without it the failure stands as
    # a red chip that can be clicked forever.
    fresh = outcomes |> MapSet.new(& &1["id"]) |> maybe_clear(opts[:clear])
    kept = Enum.reject(existing, &MapSet.member?(fresh, &1["id"]))

    Map.put(matches, level, Map.put(level_map, "providers", kept ++ outcomes))
  end

  defp maybe_clear(ids, nil), do: ids
  defp maybe_clear(ids, id), do: MapSet.put(ids, id)

  defp remember_query({:ok, item}, level, query), do: remember_query(item, level, query)
  defp remember_query({:error, _reason} = error, _level, _query), do: error

  defp remember_query(%InboxItem{} = item, level, query) do
    update_matches(item, fn matches ->
      updated =
        matches
        |> Map.get(level, %{})
        |> Map.put("query", to_string(query))
        |> Map.put("query_fields", Provider.Query.non_blank_fields(query))

      Map.put(matches, level, updated)
    end)
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
