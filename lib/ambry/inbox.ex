defmodule Ambry.Inbox do
  @moduledoc """
  The curation queue every recording passes through before clients see it.

  **The inbox is the only road into the library.** Discovery finds candidates
  and records what they are; import is what creates real records and touches
  files. Nothing here copies, links, moves or organizes anything: an item
  references its files exactly where they landed.

  A queue rather than auto-import because audiobooks have weak naming
  conventions, so the uncertain case is the common case. Automation's job is
  to make confirmation one click, not to skip the human.

  ## Discovery shape

  A downloads folder does not say consistently where one release ends and the
  next begins, so the walk decides from what it finds
  (`directory_candidate/1`). A folder holding audio directly *is* the release;
  a folder whose subfolders are plainly parts ("Disc 02", "3 of 5") is still
  one release; anything else is a container to look inside. Loose files are
  their own release.

  ## What a scan may change, and what it may not

  **Ownership decides, not the walk.** Every file the queue already holds
  belongs to something, and the walk's proposed grouping is consulted only for
  files that belong to nothing. A scan may create items from unowned files,
  give an unowned file to the item owning the folder above it, and drop a file
  no candidate in the whole walk claimed. It may never move a file between
  items, and it never changes what an imported item holds.

  That is what makes a split *and* a combine durable without a marker, by
  construction rather than by a rule the code remembers: `record_candidate/4`
  groups by owner before looking at anything else.

  Discovery hides no file because a recording was imported from it: a release
  the library already holds is exactly what an operator upgrading it to direct
  play wants to see. That provenance pre-fills the import form's replace
  decision instead.

  Whether an item's files are still there is a separate pass with a separate
  rule (`Ambry.Inbox.Reconciliation`), which asks the filesystem rather than
  the walk's claims.
  """

  use Boundary,
    deps: [Ambry, Ambry.Library, Ambry.Media, Ambry.Wanted],
    # The draft tree IS the import form's data model. Import stays internal.
    exports: [InboxItem, {Draft, []}]

  import Ecto.Query

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Duplicates
  alias Ambry.Inbox.Importer
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.Lookup
  alias Ambry.Inbox.Preflight
  alias Ambry.Inbox.Progress
  alias Ambry.Inbox.Reconciliation
  alias Ambry.Inbox.ReleaseName
  alias Ambry.Inbox.RunDiscovery
  alias Ambry.Inbox.RunImport
  alias Ambry.Inbox.RunMatch
  alias Ambry.Inbox.RunProbe
  alias Ambry.Library
  alias Ambry.Library.ImportPreference
  alias Ambry.Library.Root
  alias Ambry.Library.Source
  alias Ambry.Media.MediaFlat
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner
  alias Ambry.Media.Scanner.Tags
  alias Ambry.Repo

  require Logger

  @doc """
  Lists inbox items, most recent first.

  Options: `:status`, `:filter` (matches the path and what the draft says the
  item is), `:offset`, `:limit`.
  """
  def list_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    over_limit = limit + 1

    items =
      InboxItem
      |> filter_by_status(opts[:status])
      |> filter_by_search(opts[:filter])
      |> filter_by_issue(opts[:issue])
      |> order_by(^newest_first(opts[:status]))
      |> offset(^Keyword.get(opts, :offset, 0))
      |> limit(^over_limit)
      |> preload(:source)
      |> Repo.all()

    items_to_return = Enum.slice(items, 0, limit)

    {items_to_return, items != items_to_return}
  end

  # Two clocks: a pending item is waiting to be looked at and sorts by when
  # it was found; an imported or ignored one is a record of something the
  # operator did and sorts by `updated_at`.
  defp newest_first(status) when status in [:imported, :ignored],
    do: [desc: :updated_at, desc: :id]

  defp newest_first(_pending_or_all), do: [desc: :inserted_at, desc: :id]

  @doc """
  How many items a list would have, under the filters it lists with.

  Takes `list_items/1`'s options and ignores the paging ones, so the total
  cannot drift from what the queue is showing.
  """
  def count_items(opts \\ []) do
    InboxItem
    |> filter_by_status(opts[:status])
    |> filter_by_search(opts[:filter])
    |> filter_by_issue(opts[:issue])
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts items per status, for at-a-glance badges.
  """
  def count_by_status do
    InboxItem
    |> group_by([i], i.status)
    |> select([i], {i.status, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  What the pending pile is made of.

  Three errands wearing one word: **ready** (waiting on a human to press
  Add), **decisions needed**, and **unprepared** (no draft yet, so waiting on
  the machine).

  `issues` cuts across all three and is counted, not subtracted.
  """
  def queue_summary do
    counts =
      InboxItem
      |> where([i], i.status == :pending)
      |> select([i], %{
        pending: count(i.id),
        ready: filter(count(i.id), i.ready),
        unprepared: filter(count(i.id), is_nil(i.draft)),
        issues: filter(count(i.id), not is_nil(i.issue))
      })
      |> Repo.one()

    # The middle bucket is what the other two leave behind: counted
    # separately it could disagree with the total.
    Map.put(
      counts,
      :decisions_needed,
      counts.pending - counts.ready - counts.unprepared
    )
  end

  @doc """
  How the providers have been answering, across the queue that's still open.

  One row per recorded outcome id, because a search and a details call
  succeed and fail independently (`Ambry.Metadata.Outcome`).

  Read from the items rather than a log, so it is the same evidence the import
  form shows, and describes the open queue rather than all history.
  """
  def provider_health do
    """
    SELECT prov->>'id' AS id,
           prov->>'name' AS name,
           count(*) AS calls,
           count(*) FILTER (WHERE prov->>'status' = 'failed') AS failures,
           max(prov->>'reason') FILTER (WHERE prov->>'status' = 'failed') AS reason
    FROM inbox_items i
    CROSS JOIN LATERAL (
      SELECT i.matches->'work' AS level
      UNION ALL
      SELECT i.matches->'recording'
      UNION ALL
      SELECT value FROM jsonb_each(COALESCE(i.matches->'people', '{}'::jsonb))
    ) lv
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(lv.level->'providers') = 'array'
           THEN lv.level->'providers'
           ELSE '[]'::jsonb END
    ) AS prov
    WHERE i.status = 'pending' AND i.matches IS NOT NULL
    GROUP BY 1, 2
    ORDER BY 4 DESC, 1
    """
    |> Repo.query!([])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [id, name, calls, failures, reason] ->
      %{id: id, name: name, calls: calls, failures: failures, reason: reason}
    end)
  end

  @doc """
  One item, carrying the source its `path` and `files` are relative to.

  Preloaded here, since without it the item's two most-used columns cannot be
  read.
  """
  def get_item!(id), do: InboxItem |> Repo.get!(id) |> Repo.preload(:source)

  def fetch_item(id) do
    with {:ok, item} <- Repo.fetch(InboxItem, id), do: {:ok, Repo.preload(item, :source)}
  end

  @no_counts %{created: 0, updated: 0, skipped: 0, unreachable: 0}

  @doc """
  Scans every watched source for candidates.

  Idempotent: an item's path is its identity, so a rescan updates a known
  item rather than duplicating it and never resurrects an ignored one.

  A source that cannot be read is counted rather than failing the run, because
  "found nothing" and "couldn't look" must not look the same.

  Returns `{:ok, %{created: n, updated: n, skipped: n, unreachable: n}}`.
  """
  def discover do
    case Library.watched_sources() do
      [] -> {:error, :no_watched_sources}
      sources -> {:ok, Enum.reduce(sources, @no_counts, &merge_counts(&2, discover_one(&1)))}
    end
  end

  @doc """
  Scans one source.

  Scanning a bare path is deliberately not possible: an item with no source
  means absolute stored paths, no placement default, and a second shape for
  every function that touches an item's files.
  """
  def discover(%Source{} = source) do
    with {:ok, counts} <- scan(source) do
      {:ok, _source} = Library.mark_scanned(source)
      {:ok, counts}
    end
  end

  defp discover_one(%Source{} = source) do
    case discover(source) do
      {:ok, counts} ->
        counts

      {:error, reason} ->
        Logger.warning(fn ->
          "Couldn't scan source #{source.name} (#{source.path}): #{inspect(reason)}"
        end)

        %{unreachable: 1}
    end
  end

  defp merge_counts(acc, counts), do: Map.merge(acc, counts, fn _key, a, b -> a + b end)

  defp scan(%Source{} = source) do
    if File.dir?(source.path) do
      ledger = ledger()

      # Two passes: an owner can span several candidates, and only the whole
      # walk knows what it still holds (`record_candidate/4`).
      {creations, claims} =
        source.path
        |> candidates()
        |> Enum.map_reduce(%{}, &record_candidate(&1, &2, ledger, source))

      results = List.flatten(creations) ++ Enum.map(claims, &refresh_claim/1)

      # After the walk, asking the disk rather than the claims: this has to
      # be answerable for an item the walk skips.
      {:ok, %{missing: missing, healed: healed}} = Reconciliation.reconcile_source(source)

      {:ok,
       %{
         created: Enum.count(results, &(&1 == :created)),
         updated: Enum.count(results, &(&1 == :updated)),
         skipped: Enum.count(results, &(&1 == :skipped)),
         missing: missing,
         healed: healed,
         unreachable: 0
       }}
    else
      {:error, :watched_source_missing}
    end
  end

  @doc """
  Records what an item's files actually are: direct-play facts plus whatever
  the file claims about itself.

  Never fails the item. An unreadable candidate keeps its place with an
  `issue` explaining why, because the operator has to see it to act on it.
  """
  def probe_item(%InboxItem{} = item, opts \\ []) do
    item = Repo.preload(item, :source)

    attrs =
      case InboxItem.included(item) do
        [] -> %{issue: "no audio files found"}
        _files -> probe_recording(InboxItem.disk_files(item))
      end

    with {:ok, item} <- update_item(item, attrs) do
      # tags are what matching leans on, so it follows probing
      {:ok, _job} = match_item_async(item, opts)
      {:ok, item}
    end
  end

  @doc """
  Re-reads one item from disk and re-asks every provider about it.

  "This is wrong, look at it again", which has to mean three things:

    * **Re-read the files**, not re-probe the list captured at discovery, or
      a release fixed on disk probes the same way forever.
    * **Ask the providers again, for real**: `refresh: true` all the way down
      to `Metadata.Cache`.
    * **Actually run.** `RunMatch` is `unique` over a 60-second window and
      Oban answers a conflict with an insert that looks successful and does
      nothing, so operator-initiated work opts out of uniqueness.

  It does not re-seed the draft: new evidence appears as un-ticked records
  rather than overwriting a decision, and the caller should say so.
  """
  def rescan_item(%InboxItem{} = item) do
    with {:ok, item} <- refresh_files(item) do
      probe_item(item, refresh: true)
    end
  end

  @doc """
  Re-reads and re-queries one item in the background.

  Refused once imported: an imported item's draft is the record of what was
  imported.
  """
  def rescan_item_async(%InboxItem{status: :imported}), do: {:error, :already_imported}

  def rescan_item_async(%InboxItem{} = item) do
    %{inbox_item_id: item.id, refresh: true} |> RunProbe.new() |> Oban.insert()
  end

  # The files on disk now, not the ones discovery happened to see. Left alone
  # when the walk comes back empty, so a share that is briefly away is not
  # recorded as a release with no audio. Stored source-relative.
  defp refresh_files(%InboxItem{} = item) do
    item = Repo.preload(item, :source)

    case candidate(InboxItem.disk_path(item)) do
      [{_path, [_ | _] = files}] ->
        stored = Enum.map(files, &stored_form(&1, item.source))

        if stored == item.files do
          {:ok, item}
        else
          with {:ok, item} <- update_item(item, %{files: stored}) do
            # the draft describes files that just moved under it
            mark_draft_stale(item)
            {:ok, item}
          end
        end

      _empty_or_unreachable ->
        {:ok, item}
    end
  end

  @doc """
  Sets columns on an item, on the row as it is now.

  Reads the row again whether given an id or an item, since callers are jobs
  whose copy is minutes old.
  """
  def update_item(item_or_id, attrs)

  def update_item(%InboxItem{id: id}, attrs), do: update_item(id, attrs)

  def update_item(id, attrs) when is_integer(id) do
    with_item(id, &(&1 |> InboxItem.changeset(attrs) |> write()))
  end

  # The row as committed, held for the rest of the transaction. Everything
  # that reads an item, changes it and writes it back goes through here.
  defp with_item(id, fun) do
    Repo.transact(fn ->
      InboxItem
      |> where([i], i.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one!()
      # Callers go on to resolve paths with it.
      |> Repo.preload(:source)
      |> fun.()
    end)
  end

  # Every write reads its row first under that lock, so `unchanged?/1` is
  # answerable and a sweep with nothing to do leaves no trace.
  defp write(changeset) do
    if InboxItem.unchanged?(changeset),
      do: {:ok, changeset.data},
      else: changeset |> InboxItem.versioned() |> Repo.update()
  end

  @doc """
  An item's files as absolute disk paths, for callers holding an item whose
  source may not be loaded.
  """
  def disk_files(%InboxItem{} = item) do
    item |> Repo.preload(:source) |> InboxItem.disk_files()
  end

  @doc """
  Proposes what an item is: which work, and which recording.

  Runs after probing, since the tags it leans on come from there. Never fails
  the item: unreachable providers mean fewer candidates.
  """
  def match_item(%InboxItem{} = item, opts \\ []) do
    with {:ok, item} <- update_item(item, AutoMatch.match(item, opts)) do
      # Matching has just replaced the evidence, so an existing draft is
      # brought up to date rather than left alone. An untouched one is rebuilt
      # outright, because a retry's new record is not ticked and re-deriving
      # from the ticked set would ignore it; once a human has decided
      # anything, `resettle/2` re-derives around them.
      cond do
        is_nil(item.draft) ->
          rebuild_draft(item)

        Draft.curated?(item.draft) ->
          update_draft_with(item, &Draft.Edit.resettle/2)

        true ->
          rebuild_draft(item)
      end
    end
  end

  @doc """
  Which providers were asked about this item and couldn't answer.

  Not "found nothing", which is an answer: this is the provider that was
  down, rate-limited or misconfigured, at any level. `RunMatch` reads it to
  decide whether it is actually finished.
  """
  def unreached_providers(%InboxItem{matches: matches}) when is_map(matches) do
    people = matches |> Map.get("people", %{}) |> Map.values()

    [Map.get(matches, "work"), Map.get(matches, "recording") | people]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&(Map.get(&1, "providers") || []))
    |> Enum.filter(&(&1["status"] == "failed"))
    |> Enum.map(& &1["id"])
    |> Enum.uniq()
  end

  def unreached_providers(_item), do: []

  @doc """
  Proposes matches for one item in the background.

  A refreshing run opts out of `RunMatch`'s uniqueness window, which exists
  to collapse the duplicate jobs a whole-source rescan produces.
  """
  def match_item_async(%InboxItem{} = item, opts \\ []) do
    if Keyword.get(opts, :refresh, false) do
      %{inbox_item_id: item.id, refresh: true}
      |> RunMatch.new(unique: false)
      |> Oban.insert()
    else
      %{inbox_item_id: item.id} |> RunMatch.new() |> Oban.insert()
    end
  end

  @doc """
  Re-derives queued drafts that the library just moved under.

  A draft is a snapshot of the library taken when the item was matched, and
  import executes it exactly. Without this, two queued items implying the same
  new person each create their own.

  It re-points references rather than deciding: `Seed.relink/2` turns a credit
  or series that meant to *create* something into a *link* when exactly one
  thing of that name now exists, and the affected credit says so before the
  operator imports. Narrower than a re-seed, which would re-open answered
  questions.
  """
  def refresh_siblings(%InboxItem{} = imported) do
    case sibling_names(imported.draft) do
      [] -> :ok
      names -> names |> siblings_of(imported) |> Enum.each(&refresh_draft/1)
    end
  end

  # Everything this import just put into the library that another queued item
  # might also be about to create.
  defp sibling_names(nil), do: []

  defp sibling_names(%Draft{} = draft) do
    work = draft.work || %{}
    recording = draft.recording || %{}

    [
      Enum.map(Map.get(work, :authors) || [], & &1.name),
      Enum.map(Map.get(recording, :narrators) || [], & &1.name),
      Enum.map(Map.get(work, :series) || [], & &1.name),
      Enum.map(draft.people || [], &Draft.Field.value(&1.name))
    ]
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))
    |> Enum.uniq()
  end

  # A cheap candidate filter: a false positive costs an idempotent
  # re-derivation, and scanning every pending item costs a rebuild each.
  defp siblings_of(names, %InboxItem{} = imported) do
    condition =
      Enum.reduce(names, dynamic(false), fn name, acc ->
        dynamic(
          [i],
          ^acc or ilike(fragment("?::text", i.draft), ^"%#{escape_like(name)}%")
        )
      end)

    InboxItem
    |> where([i], i.status == :pending and i.id != ^imported.id and not is_nil(i.draft))
    |> where(^condition)
    |> Repo.all()
  end

  defp escape_like(value), do: String.replace(value, ~r/[\\%_]/, "\\\\\\0")

  # Never fatal: a sibling that won't re-derive is a stale proposal to fix on
  # the form, not a reason to fail an import that already committed.
  defp refresh_draft(%InboxItem{} = item) do
    case update_draft_with(item, &Seed.relink/2) do
      {:ok, _item} ->
        :ok

      {:error, _reason} ->
        Logger.warning(fn -> "Inbox: couldn't refresh draft for item #{item.id}" end)
        :ok
    end
  end

  @doc """
  Stages the import: turns what was found into a tree of decisions.

  Runs after matching, and is what the queue's Ready badge and the import
  form both read. Only ever builds where there is no draft yet.
  """
  # An imported item's draft is the record of what was imported; nothing may
  # touch it, healing included.
  def prepare_draft(%InboxItem{status: :imported} = item), do: {:ok, item}

  def prepare_draft(%InboxItem{} = item) do
    item
    |> update_draft_with(fn
      nil, fresh -> Seed.build(fresh)
      draft, fresh -> draft |> refresh_destination(fresh) |> refresh_replacement(fresh)
    end)
    |> case do
      # Imported while this caller held the row. A no-op, not a failure: the
      # form asks on mount and a read-only page is a fine answer.
      {:error, :already_imported} -> {:ok, item}
      result -> result
    end
  end

  # An unanswered decision is a default, and one frozen at match time is
  # wrong the moment what it was derived from changes. So unanswered
  # decisions are re-derived on every prepare and answered ones never are,
  # which is what `chosen` and `curated` exist to draw.
  defp refresh_destination(%Draft{} = draft, item) do
    %{draft | destination: Seed.redefault(draft.destination || %Destination{}, item)}
  end

  defp refresh_replacement(%Draft{} = draft, item) do
    %{draft | replacement: Seed.repropose(draft.replacement || %Replacement{}, item)}
  end

  @doc """
  Throws away the staged import and seeds a fresh one from current evidence.

  The escape hatch when a draft was built against the wrong match. Never
  automatic.
  """
  def rebuild_draft(%InboxItem{} = item) do
    update_draft_with(item, fn _discarded, fresh -> Seed.build(fresh) end)
  end

  @doc """
  Applies a transformation to the draft the row actually holds.

  **The way to change a draft.** The transformation is handed the *committed*
  draft rather than one the caller read earlier, so a sweep over hundreds of
  drafts cannot write back minutes-old copies.

  May return `nil` for "nothing to write". Runs inside the transaction, so
  keep it to library reads and never a provider call.
  """
  def update_draft_with(item_or_id, fun)

  def update_draft_with(%InboxItem{id: id}, fun), do: update_draft_with(id, fun)

  def update_draft_with(id, fun) when is_integer(id) do
    with_item(id, fn
      # An imported item's draft is the frozen record of that import.
      %InboxItem{status: :imported} -> {:error, :already_imported}
      item -> write_draft(item, fun.(item.draft, item))
    end)
  end

  defp write_draft(item, nil), do: {:ok, item}

  defp write_draft(item, %Draft{} = draft),
    do: item |> InboxItem.put_draft(draft |> reconcile_people(item) |> dump()) |> write()

  # Every referenced key has a decision, on every write: an edit touching
  # `person_keys` can otherwise leave the two out of step, and
  # `Draft.people_for/2` silently drops what it cannot resolve. Only the gap
  # is repaired, never the whole set.
  defp reconcile_people(%Draft{} = draft, %InboxItem{} = item) do
    case Draft.referenced_keys(draft) -- Enum.map(draft.people, & &1.key) do
      [] -> draft
      _missing -> Seed.reseed_people(draft, item)
    end
  end

  @doc """
  Saves the import form's own params.

  The one draft write that cannot be replayed against a newer draft, since
  its attrs are a rendered form. Everything else goes through
  `update_draft_with/2`, which re-derives.

  Returns `{:error, :stale}` when the row has moved since the form was
  rendered. Every save recomputes readiness.
  """
  def update_draft(%InboxItem{status: :imported}, _attrs), do: {:error, :already_imported}

  def update_draft(%InboxItem{} = item, attrs) do
    item
    |> InboxItem.put_draft(attrs)
    |> InboxItem.versioned()
    |> Repo.update(stale_error_field: :lock_version)
    |> case do
      {:ok, item} ->
        {:ok, item}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :lock_version),
          do: {:error, :stale},
          else: {:error, changeset}
    end
  end

  @doc """
  Every set of library records that name the same thing.

  Covers every record in the library, however it got there, but the
  definition of *the same* is the importer's and lives here. See
  `Ambry.Inbox.Duplicates`.
  """
  defdelegate duplicates, to: Duplicates, as: :check

  @doc """
  The sets still asking a question and the sets already answered, in one pass.
  """
  defdelegate duplicates_report, to: Duplicates, as: :report

  @doc """
  How many such sets there are, and how many records were examined.
  """
  defdelegate duplicate_count, to: Duplicates, as: :count

  defdelegate duplicates_scanned, to: Duplicates, as: :scanned

  @doc """
  Records a set of records as deliberately distinct, and puts one back.

  Two series that fold to one key may be two real series; the report cannot
  tell. This is where the operator says.
  """
  defdelegate dismiss_duplicates(kind, record_ids), to: Duplicates, as: :dismiss

  defdelegate restore_duplicates(kind, record_ids), to: Duplicates, as: :restore

  @doc """
  How a provider record is referred to: its provider and that provider's id.
  """
  defdelegate record_ref(record), to: AutoMatch, as: :ref

  @doc """
  Whether two spellings mean one human, as one comparable key.

  Matching's own rule, so the edit forms decide it exactly the way an import
  does: initials, punctuation and accents all fold.
  """
  defdelegate person_key(name), to: AutoMatch

  @doc """
  Scoring hints from a library record's own fields, so the edit forms rank
  provider records the way matching ranks them against an item's tags. The
  scoring itself is `score_records/3`.
  """
  defdelegate form_hints(fields), to: AutoMatch

  @doc """
  What this item's tags and release name say it is: the same hints matching
  searched with, so the form's boxes start from what was actually looked for.
  """
  defdelegate hints(item), to: AutoMatch

  @doc "Provider books → scored, ranked evidence records (top-N per provider)."
  defdelegate score_records(books, entry, hints), to: AutoMatch, as: :records_from

  @doc "Audio editions of the given work records, from editions-capable providers."
  defdelegate editions_of(records, hints, opts \\ []), to: AutoMatch, as: :editions_for

  @doc "The records that look like they're about the same thing as the best one."
  defdelegate top_group(records), to: AutoMatch

  @doc """
  Fetches the full record behind a thin search hit.
  """
  defdelegate hydrate_record(item, level, ref), to: Lookup, as: :hydrate

  @doc """
  Asks every editions-capable database what recordings a work is known to have.
  """
  defdelegate fetch_editions(item, work_refs), to: Lookup, as: :editions

  @doc """
  Runs an operator-written search and adds whatever it returns.
  """
  defdelegate research(item, level, fields), to: Lookup
  defdelegate research_person(item, key, name), to: Lookup

  @doc """
  Asks one provider again — the one that was unreachable during matching.
  """
  defdelegate retry_provider(item, level, provider_id), to: Lookup

  @doc """
  A changeset for the staged import, for the form to render.
  """
  def change_draft(%InboxItem{} = item, attrs \\ %{}) do
    InboxItem.put_draft(item, attrs)
  end

  @doc """
  What import will do with this item's bytes, decided before it's asked.

  Placement can fail for reasons no amount of curation fixes: a different
  filesystem from the library root, an occupied destination, no root at all.
  Working them out up front lets the form refuse to offer a button that fails.

  Returns a map with a human `:summary` and a `:blocker`, nil when placement
  will work.
  """
  def destination_preflight(%InboxItem{} = item) do
    item = Repo.preload(item, :source)

    case chosen_root(item) do
      {:error, reason} -> %{blocker: describe_error(reason)}
      {:ok, root} -> %{blocker: hardlink_blocker(item, chosen_policy(item), root)}
    end
  end

  # The draft's choice, or the default the seed put there. No source-level
  # fallback: with no root settled there is no pairing to recall.
  defp chosen_policy(%InboxItem{draft: %{destination: %{policy: policy}}})
       when not is_nil(policy), do: policy

  defp chosen_policy(%InboxItem{}), do: nil

  # The root the draft settled on, not one derived from the source: inputs
  # and outputs are independent, so this is a decision rather than a lookup.
  defp chosen_root(%InboxItem{draft: %{destination: %{root_id: id}}}) when is_integer(id) do
    case Repo.get(Root, id) do
      %Root{} = root -> {:ok, root}
      nil -> {:error, :no_library_root}
    end
  end

  # "No root chosen" and "no root exists" are different problems with
  # different fixes.
  defp chosen_root(_item) do
    case Library.list_roots() do
      [] -> {:error, :no_library_root}
      _some -> {:error, :ambiguous_library_root}
    end
  end

  # A hardlink cannot cross a filesystem, and silently copying instead is the
  # storage doubling this exists to prevent. Symlink gets no blocker: it has
  # no precondition to fail.
  defp hardlink_blocker(item, :hardlink, root) do
    case hardlinkable(item, root) do
      {:ok, true} -> nil
      {:ok, false} -> describe_error({:cross_filesystem, first_file(item), root.path})
      {:error, _reason} -> "Couldn't tell whether these are on the same filesystem."
    end
  end

  defp hardlink_blocker(_item, _policy, _root), do: nil

  # Asked of the item's real files, not its source's path: the answer that
  # gates a placement has to be about the bytes being placed.
  defp hardlinkable(%InboxItem{files: [_ | _]} = item, root),
    do: Library.same_filesystem?(Path.dirname(first_file(item)), root.path)

  defp hardlinkable(%InboxItem{}, _root), do: {:error, :no_files}

  defp first_file(%InboxItem{} = item), do: item |> InboxItem.disk_files() |> hd()

  @doc """
  A draft as params, for staging it back onto an item.
  """
  def dump_draft(%Draft{} = draft), do: dump(draft)

  # Embedded schema structs go back through `cast_embed`, which wants params.
  defp dump(%Draft{} = draft) do
    draft |> Ecto.embedded_dump(:json) |> stringify()
  end

  defp stringify(%{} = map) when not is_struct(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  @doc """
  Approves an item into the library.

  Creates the whole entity graph in one transaction: book, credits, series,
  the recording and its tracks. Nothing is published; the recording is
  created `pending`.
  """
  def import_item(%InboxItem{} = item) do
    if Reconciliation.present?(item), do: do_import_item(item), else: {:error, :files_missing}
  end

  defp do_import_item(%InboxItem{} = item) do
    case Importer.import_item(item) do
      {:ok, media} ->
        # Bookkeeping, after the records are committed. Neither may fail the
        # import, and neither may skip the other.
        after_commit(item, "remember the placement", fn -> remember_placement(item) end)
        after_commit(item, "relink sibling drafts", fn -> refresh_siblings(item) end)
        {:ok, media}

      {:error, reason} = error ->
        # A flash lasts one page load and a discarded job a day, so the
        # reason goes on the item itself.
        update_item(item, %{issue: describe_error(reason)})
        error
    end
  end

  # Post-commit work is untidy when it fails, not broken: `RunImport` is
  # `max_attempts: 1`, so a raise here discards the job for a release the
  # library has.
  defp after_commit(%InboxItem{} = item, what, work) do
    work.()
    :ok
  rescue
    error ->
      Logger.error(fn ->
        "Imported inbox item #{item.id}, but couldn't #{what}: " <>
          Exception.message(error)
      end)

      :ok
  end

  # Remembered after the fact rather than when the operator picked: a choice
  # made on a release that then failed to place is not what the source does.
  defp remember_placement(%InboxItem{} = item) do
    %InboxItem{source: source, draft: draft} = Repo.preload(item, :source)

    with %Source{} = source <- source,
         %Draft{destination: %Destination{root_id: id, policy: policy}} when not is_nil(policy) <-
           draft,
         %Root{} = root <- id && Repo.get(Root, id) do
      previous = Library.recall_placement(source)
      {:ok, _preference} = Library.remember_placement(source, root, policy)

      if moved?(previous, root, policy), do: refresh_queued_destinations(source)
    end

    :ok
  end

  defp moved?(nil, _root, _policy), do: true
  defp moved?(%ImportPreference{library_root_id: id, policy: p}, %Root{id: id}, p), do: false
  defp moved?(%ImportPreference{}, _root, _policy), do: true

  # The default just moved, so every queued item following it proposes the
  # wrong thing, and the Ready badge reads a stored column. Only runs when the
  # memory actually changed.
  defp refresh_queued_destinations(%Source{} = source) do
    InboxItem
    |> where([i], i.source_id == ^source.id and i.status == :pending)
    |> Repo.all()
    |> Enum.each(fn item ->
      if item.draft, do: prepare_draft(item)
    end)
  end

  @doc """
  Queues the import and hands the operator back their afternoon.

  Placing a release is the longest thing the inbox does, so the job belongs
  to the server; run inside the form it would be a spinner the operator can
  kill by closing the tab.

  Refuses an item already in the library, and refuses once when the draft
  would create something the library may already have
  (`{:error, {:collisions, findings}}`, see `Ambry.Inbox.Preflight`). Pass the
  findings back as `:acknowledged` and the import proceeds only if the library
  still says exactly that.
  """
  def import_item_async(item, opts \\ [])

  def import_item_async(%InboxItem{status: :imported}, _opts), do: {:error, :already_imported}

  def import_item_async(%InboxItem{} = item, opts) do
    case Preflight.check(item) do
      [] -> enqueue_import(item)
      findings -> acknowledged(item, findings, Keyword.get(opts, :acknowledged))
    end
  end

  defp acknowledged(item, findings, findings), do: enqueue_import(item)
  defp acknowledged(_item, findings, _stale_or_absent), do: {:error, {:collisions, findings}}

  defp enqueue_import(item) do
    %{inbox_item_id: item.id} |> RunImport.new() |> Oban.insert()
  end

  @doc """
  Says what went wrong in a sentence the operator can act on.

  Shared between the flash and the `issue` recorded on the item.
  """

  def describe_error(:no_published_date),
    do:
      "No publication date, and one can't be invented. Match a book, or tag the file with a date."

  def describe_error(:no_title),
    do: "Nothing here says what this is. Match a book, or tag the file with a title."

  def describe_error({:unreadable, _reason}),
    do: "Couldn't read the file. It may have moved since it was found."

  def describe_error({:source_missing, _path}), do: "The file has gone away since it was found."

  # The same fact `{:source_missing, _}` reports from inside placement, found
  # by the scan instead of by the write.
  def describe_error(:files_missing),
    do: "This item's files are gone. Nothing can be imported from it until they come back."

  # Says what to do rather than only what failed.
  def describe_error({:cross_filesystem, _source, _destination}),
    do:
      "These files and the library root are on different filesystems, so they can't be " <>
        "hardlinked. Choose copy or move, or a root on the same disk."

  # Occupied by a recording is a bug: every recording's name carries its own
  # token. Occupied by an unreferenced file is the ordinary case, an import
  # whose copy landed and whose transaction rolled back.
  def describe_error({:destination_exists, path}) do
    if file_in_use?(path) do
      "Another audiobook's files are already at #{path}. That should be " <>
        "impossible, so this is a bug worth reporting."
    else
      "A file nothing in the library references is at #{path}, likely left " <>
        "behind by an interrupted import. Delete it and import again."
    end
  end

  def describe_error(:no_library_root),
    do: "There's no library root to import into. Add one under Locations."

  def describe_error(:ambiguous_library_root),
    do: "There's more than one library root. Choose which one this folder imports into."

  def describe_error(:already_imported), do: "Already in the library; this item is read-only."

  def describe_error(:not_divisible),
    do: "These files are all in one folder, so splitting by folder would change nothing."

  def describe_error(:last_file),
    do: "This is the only file left in the audiobook. Ignore the whole item instead."

  def describe_error(:not_held), do: "This item doesn't hold that file any more."

  # Names the count rather than the decisions, because the form lists them
  # properly and this is only reachable from the queue.
  def describe_error({:unresolved, outstanding}) do
    count = length(outstanding)

    "#{count} thing#{if count > 1, do: "s"} still to settle before this can be imported. " <>
      "Open it to see what."
  end

  # The findings need the form, which is where the answer can be given, so
  # this counts them and sends the operator there.
  def describe_error({:collisions, findings}) do
    count = length(findings)

    "#{count} thing#{if count > 1, do: "s"} here may already be in the library. " <>
      "Open it to see what."
  end

  def describe_error(_reason), do: "Couldn't add this to the library."

  defp file_in_use?(path), do: Repo.exists?(where(MediaTrack, path: ^path))

  @doc """
  What is happening to each of these items in the background.
  """
  defdelegate progress(items), to: Progress, as: :statuses

  @doc """
  The audiobooks these items became, keyed by **item** id.

  One query for a page of items, since the queue renders an imported row as
  the audiobook it produced.

  An imported item can have no audiobook, because deleting one nilifies the
  link rather than taking the record of the import with it.
  """
  def audiobooks(items) do
    media_ids = items |> Enum.map(& &1.media_id) |> Enum.reject(&is_nil/1)

    if media_ids == [] do
      %{}
    else
      by_media_id =
        MediaFlat
        |> where([m], m.id in ^media_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      items
      |> Enum.flat_map(fn item ->
        case Map.fetch(by_media_id, item.media_id) do
          {:ok, audiobook} -> [{item.id, audiobook}]
          :error -> []
        end
      end)
      |> Map.new()
    end
  end

  @doc """
  What a background job is doing to one item.
  """
  defdelegate job_status(item), to: Progress, as: :status
  defdelegate job_statuses(items), to: Progress, as: :statuses
  defdelegate busy?(status), to: Progress

  @doc """
  Takes an item out of the queue without touching its files.

  Dismissals are remembered by path, so a rescan doesn't offer it again.
  """
  def ignore_item(%InboxItem{} = item), do: update_item(item, %{status: :ignored})

  def restore_item(%InboxItem{} = item), do: update_item(item, %{status: :pending})

  @doc """
  Whether this item's files are all still there.

  One answer, because the badge, the import and the re-open control all ask
  it and two of them disagreeing is worse than any being wrong.
  """
  defdelegate item_files_present?(item), to: Reconciliation, as: :present?

  @doc """
  Puts an imported item back in the queue, so its decisions can be made again.

  Not an undo: nothing in the library is touched, no files move, and the
  recording goes on playing what it was playing. All that changes is that this
  item is work again, so putting a replaced audiobook back on its old files is
  then an ordinary import rather than a reversal mechanism with its own rules.

  **Its claim on the audiobook is dropped**, because a pending item has not
  imported anything. The draft stays exactly as it was: it is the operator's
  curation.

  Refused when the files are gone, since re-opening could only produce an item
  that cannot import.
  """
  def reopen_item(%InboxItem{status: :imported} = item) do
    if Reconciliation.present?(item) do
      item
      |> InboxItem.changeset(%{status: :pending, media_id: nil, issue: nil})
      |> Ecto.Changeset.put_change(:superseded_by_id, nil)
      |> InboxItem.versioned()
      |> Repo.update()
    else
      {:error, :files_missing}
    end
  end

  def reopen_item(%InboxItem{}), do: {:error, :not_imported}

  def delete_item(%InboxItem{} = item), do: Repo.delete(item)

  @doc """
  Splits a wrongly-grouped item into several, `by: :folder` or `by: :file`.

  The folder-based grouping fails at two grains: two unrelated single-file
  books can share a folder, and a set of subfolders can be five recordings
  rather than one release in five parts. Only the operator can tell, so the
  split asks at which grain it was wrong:

    * `:folder` — one item per folder, each free to take its own part number.
    * `:file` — one item per file, for a folder that was never one release.

  Children are inserted in the shape discovery gives an item of that grain,
  with a fresh probe and match queued: the parent's described its first file
  only. A split survives rescans without a marker, because discovery respects
  a finer partition that already exists (`record_candidate/4`).

  Refused once imported, below two files, and when the chosen grain would not
  divide anything, which would delete and recreate the item for nothing.
  """
  def split_item(item, by \\ :file)

  def split_item(%InboxItem{status: :imported}, _by), do: {:error, :already_imported}

  def split_item(%InboxItem{files: files}, _by) when length(files) < 2,
    do: {:error, :not_multi_file}

  def split_item(%InboxItem{} = item, by) do
    case split_groups(item, by) do
      [_one] -> {:error, :not_divisible}
      groups -> regroup([item], groups)
    end
  end

  @doc """
  Takes one file out of an item's audiobook, or puts it back.

  A release can ship the same part twice at two bitrates, and nothing but a
  listener can tell. Splitting does not help (the rest is one audiobook) and
  neither does ignoring (that takes the whole item out), so this is the grain
  in between.

  **The file is not let go of.** It stays in `files`, which is what discovery
  reads to decide ownership: an item that shortened its list would be handed
  the file back as an item of its own on the next scan, and every scan after.
  It is listed and struck through rather than hidden, because a form that
  quietly showed six of seven files would be lying about what it holds.

  The recording changes, so the item is read again. An untouched draft is
  rebuilt around the new reading; a curated one is left alone and says it is
  out of date.

  Refused on an imported item, for a file the item doesn't hold, and for the
  last one standing.
  """
  def exclude_file(%InboxItem{} = item, file), do: set_included(item, file, false)

  def include_file(%InboxItem{} = item, file), do: set_included(item, file, true)

  defp set_included(%InboxItem{status: :imported}, _file, _included?),
    do: {:error, :already_imported}

  defp set_included(%InboxItem{} = item, file, included?) do
    cond do
      file not in item.files -> {:error, :not_held}
      not included? and InboxItem.included(item) == [file] -> {:error, :last_file}
      true -> reread(item, excluded_after(item, file, included?))
    end
  end

  defp excluded_after(%InboxItem{excluded_files: excluded}, file, true), do: excluded -- [file]

  defp excluded_after(%InboxItem{excluded_files: excluded}, file, false),
    do: Enum.uniq(excluded ++ [file])

  defp reread(%InboxItem{} = item, excluded) do
    with {:ok, item} <- update_item(item, %{excluded_files: excluded}) do
      # The draft describes a recording that just changed length.
      mark_draft_stale(item)
      {:ok, _job} = probe_item_async(item)
      {:ok, item}
    end
  end

  @doc """
  The other items this one would be combined with, and the folder they'd
  become — or nil when there is nothing to offer.

  The offer is *the folder holding this item* and everything the queue still
  has waiting under it, which is the shape the mistake comes in: a release
  whose parts sit in subfolders the walk could not read as parts.

  Nothing is offered for an item at the top of its source, where every item
  shares the root and the offer would be the whole downloads folder.
  """
  def combine_group(%InboxItem{status: :pending} = item) do
    with folder when not is_nil(folder) <- parent_folder(item),
         [_one, _two | _rest] = items <- items_under(folder, item.source_id),
         target when not is_nil(target) <- common_folder(items) do
      %{folder: target, items: items}
    else
      _nothing_to_offer -> nil
    end
  end

  def combine_group(%InboxItem{}), do: nil

  @doc """
  Combines this item with the rest of its folder (`combine_group/1`) into one.
  """
  def combine_item(%InboxItem{} = item) do
    case combine_group(item) do
      nil -> {:error, :nothing_to_combine}
      %{items: items} -> combine_items(items)
    end
  end

  @doc """
  Merges several items into a single one for the folder that holds them.

  The opposite mistake to a split. A folder whose subfolders do not *say* they
  are parts reads as a container of releases, deliberately, because a numbered
  title is its own book far more often than it is disc two of something. When
  it is not, the queue has several items that are one audiobook.

  They become one item at the folder they share, holding every file in
  `audio_files/1`'s order so a rescan agrees. The parts' drafts are **not**
  merged: each described a different audiobook, and half of three wrong
  answers is not an answer, so the combined item is probed and matched fresh.

  Refused when any of them is imported, below two items, when they do not all
  come from one source, and when the folder they share is the source root,
  where the item would own every file that ever lands there.
  """
  def combine_items(items)

  def combine_items(items) when length(items) < 2, do: {:error, :not_multiple}

  def combine_items([%InboxItem{} | _rest] = items) do
    cond do
      Enum.any?(items, &(&1.status == :imported)) -> {:error, :already_imported}
      not one_source?(items) -> {:error, :different_sources}
      folder = common_folder(items) -> combine_under(folder, items)
      true -> {:error, :no_shared_folder}
    end
  end

  defp one_source?(items), do: items |> Enum.map(& &1.source_id) |> Enum.uniq() |> length() == 1

  defp combine_under(folder, items) do
    if occupied?(folder, items) do
      {:error, :path_taken}
    else
      files = items |> Enum.flat_map(& &1.files) |> Enum.sort(NaturalOrder)

      with {:ok, [combined]} <- regroup(items, [{folder, files}]), do: {:ok, combined}
    end
  end

  # An item at the path the combined one would take, that isn't one of the
  # items being replaced. `path` is unique across the whole table, so this
  # asks the same question the constraint would, early enough to refuse with
  # a reason rather than a constraint error.
  defp occupied?(folder, items) do
    ids = Enum.map(items, & &1.id)

    InboxItem
    |> where([i], i.path == ^folder and i.id not in ^ids)
    |> Repo.exists?()
  end

  # The items still waiting under a folder, including one sitting at the
  # folder itself. `starts_with` rather than a LIKE: release folders are full
  # of `%` and `_`, and a pattern would read them as wildcards.
  defp items_under(folder, source_id) do
    InboxItem
    |> where([i], i.source_id == ^source_id and i.status == :pending)
    |> where([i], i.path == ^folder or fragment("starts_with(?, ?)", i.path, ^(folder <> "/")))
    |> order_by([i], i.path)
    |> Repo.all()
    |> Repo.preload(:source)
  end

  defp parent_folder(%InboxItem{path: path}) do
    case Path.dirname(path) do
      "." -> nil
      folder -> folder
    end
  end

  # The deepest folder holding all of them, or nil when that is the source
  # root. Read off the paths rather than their parents, so an item sitting
  # *at* the folder counts as being in it.
  defp common_folder(items) do
    items
    |> Enum.map(&Path.split(&1.path))
    |> Enum.reduce(&common_prefix/2)
    |> case do
      [] -> nil
      segments -> Path.join(segments)
    end
  end

  defp common_prefix(a, b) do
    a |> Enum.zip(b) |> Enum.take_while(fn {x, y} -> x == y end) |> Enum.map(&elem(&1, 0))
  end

  # One grouping replaced by another, each new item read from scratch. Split
  # and combine are the same move.
  defp regroup(items, groups) do
    Repo.transact(fn ->
      with :ok <- delete_items(items),
           {:ok, children} <- insert_children(hd(items), groups) do
        # In the transaction: a job for a child that was not created must not
        # exist either.
        Enum.each(children, fn child -> {:ok, _job} = probe_item_async(child) end)
        {:ok, children}
      end
    end)
  end

  defp delete_items(items) do
    ids = Enum.map(items, & &1.id)
    {deleted, _returning} = InboxItem |> where([i], i.id in ^ids) |> Repo.delete_all()

    # Someone else got there first, and the grouping was decided about items
    # that are no longer what the queue holds.
    if deleted == length(ids), do: :ok, else: {:error, :stale}
  end

  @doc """
  How many items each grain would produce, for the controls that offer them.

  **A grain only appears when it divides further than the coarser one.** A
  set of three folders holding one file each is the same three items either
  way, and offering both asks the operator to choose between identical
  outcomes: `%{folder: 5, file: 35}` on a GraphicAudio set, `%{folder: 3}` on
  three books in three folders, `%{file: 3}` on three files in one.
  """
  def split_grains(%InboxItem{} = item) do
    folders = length(split_groups(item, :folder))
    files = length(split_groups(item, :file))

    %{}
    |> put_if(:folder, folders, folders > 1)
    |> put_if(:file, files, files > folders)
  end

  # Discovery order within a group is playing order; re-sorting reorders a
  # book.
  defp split_groups(%InboxItem{files: files}, :file), do: Enum.map(files, &{&1, [&1]})

  defp split_groups(%InboxItem{files: files}, :folder) do
    files
    |> Enum.group_by(&Path.dirname/1)
    |> Enum.sort_by(fn {dir, _files} -> dir end)
  end

  defp insert_children(%InboxItem{} = item, groups) do
    groups
    |> Enum.reduce_while({:ok, []}, fn {path, files}, {:ok, acc} ->
      %InboxItem{}
      |> InboxItem.changeset(%{path: path, files: files, source_id: item.source_id})
      |> Repo.insert()
      |> case do
        {:ok, child} -> {:cont, {:ok, [child | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, children} -> {:ok, Enum.reverse(children)}
      error -> error
    end
  end

  @doc """
  Runs discovery in the background.
  """
  def discover_async do
    %{} |> RunDiscovery.new() |> Oban.insert()
  end

  @doc """
  Probes one item in the background.
  """
  def probe_item_async(%InboxItem{} = item) do
    %{inbox_item_id: item.id} |> RunProbe.new() |> Oban.insert()
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [i], i.status == ^status)

  # Matches the path AND what the draft says the item is, which is why the
  # column exists: an item whose folder names only the title is still findable
  # by its author. The phrase is a parameter to `plainto_tsquery`, so there is
  # no pattern for a typed `%` to be a wildcard in.
  defp filter_by_search(query, blank) when blank in [nil, ""], do: query

  defp filter_by_search(query, filter) do
    if String.trim(filter) == "" do
      query
    else
      # No emptiness guard: a phrase producing no lexemes matches nothing,
      # which `@@ NULL` being NULL already says. Guarded, a word the stemmer
      # drops (`don`, `will`, `can`) would show the whole queue.
      where(query, [i], fragment("? @@ ambry_tsquery(?, 'all', true)", i.search_vector, ^filter))
    end
  end

  # An issue cuts across the buckets rather than replacing them, so it narrows
  # whatever list is showing instead of being a status of its own.
  defp filter_by_issue(query, true), do: where(query, [i], not is_nil(i.issue))
  defp filter_by_issue(query, _no), do: query

  defp candidates(root) do
    root |> entries() |> Enum.flat_map(&candidate/1)
  end

  defp candidate(path) do
    cond do
      File.dir?(path) -> directory_candidate(path)
      audio_file?(path) -> [{path, [path]}]
      true -> []
    end
  end

  # Where one release ends and the next begins, which a downloads folder does
  # not answer consistently. Three shapes turn up in practice, and the rule
  # has to tell them apart:
  #
  #   Dan Brown - Origin/*.mp3          one book, audio sitting right there
  #   Discworld/<43 titles>/*.mp3       a whole series in one folder
  #   The Way of Kings/{1 of 5, ...}    one book split across subfolders
  #
  # Taking every immediate child as a release makes the series one huge item;
  # recursing to the deepest audio-bearing folder shatters the split book into
  # five. So: audio in hand means this is the release, subfolders that are
  # plainly *parts* keep the parent, and anything else is a container.
  defp directory_candidate(dir) do
    direct_audio = dir |> entries() |> Enum.filter(&audio_file?/1)
    subdirs = dir |> entries() |> Enum.filter(&File.dir?/1)

    cond do
      direct_audio != [] -> [{dir, audio_files(dir)}]
      subdirs == [] -> []
      Enum.all?(subdirs, &part_folder?/1) -> one_candidate(dir)
      true -> Enum.flat_map(subdirs, &candidate/1)
    end
  end

  defp one_candidate(dir) do
    case audio_files(dir) do
      [] -> []
      files -> [{dir, files}]
    end
  end

  # In `ReleaseName` because two callers read it: this walk, and an item named
  # after one of those folders, which has to say what it is a part *of*.
  defp part_folder?(dir), do: dir |> Path.basename() |> ReleaseName.part_folder?()

  defp entries(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries |> Enum.sort(NaturalOrder) |> Enum.map(&Path.join(dir, &1))

      {:error, reason} ->
        Logger.warning(fn -> "Couldn't read #{dir}: #{inspect(reason)}" end)
        []
    end
  end

  # By hand rather than `Path.wildcard/2`: release folders are full of glob
  # metacharacters ("[M4B]" is a character class) and must not go missing.
  defp audio_files(dir) do
    dir
    |> walk()
    |> Enum.filter(&audio_file?/1)
    |> Enum.sort(NaturalOrder)
  end

  defp walk(dir) do
    dir
    |> entries()
    |> Enum.flat_map(fn path -> if File.dir?(path), do: walk(path), else: [path] end)
  end

  defp audio_file?(path) do
    path |> Path.extname() |> String.downcase() |> Kernel.in(Scanner.extensions())
  end

  @doc false
  # **Ownership decides, not the walk.** Which release a known file belongs to
  # is settled, whatever the operator split or combined, and re-walking its
  # folder may not have an opinion. Structural rather than remembered: this
  # groups by owner *before* looking at anything, so the walk's proposed
  # grouping is only ever consulted for files with no owner.
  #
  # **The library is not an owner.** Skipping files a recording was imported
  # from would hide the release from an operator upgrading it. That provenance
  # pre-fills the replace decision (`Ambry.Media.imported_from/1`) instead.
  #
  # **What an owner still holds is answered by the whole walk, not by one
  # candidate**, which is what makes a combined item durable: the walk offers
  # its three subfolders as three candidates, and refreshing from each in turn
  # would leave the item holding whichever ran last. So a candidate only
  # *claims* files here, and the claims settle once the source is walked.
  defp record_candidate({path, files}, claims, ledger, source) do
    by_owner = Enum.group_by(files, &owner_of(&1, ledger))
    orphans = Map.get(by_owner, nil, [])

    creations = if orphans == [], do: [], else: List.wrap(adopt(path, files, orphans, source))

    claims =
      by_owner
      |> Map.delete(nil)
      |> Enum.reduce(claims, fn {%InboxItem{} = item, theirs}, claims ->
        # Walk order, which is what a single candidate for the whole folder
        # would have produced.
        Map.update(claims, item.id, {item, theirs}, fn {item, held} -> {item, held ++ theirs} end)
      end)

    {creations, claims}
  end

  defp refresh_claim({_id, {item, files}}), do: refresh_owner(item, files)

  # The item that already lists it, then the nearest item above it: that is
  # how a new file in a known release folder joins that release.
  defp owner_of(file, ledger) do
    cond do
      item = ledger.by_file[file] -> item
      item = nearest_owner(file, ledger.by_path) -> item
      true -> nil
    end
  end

  # Up from the file rather than across every item: depth is single digits,
  # the item list is hundreds, and this runs per file.
  defp nearest_owner(file, by_path) do
    file
    |> Stream.unfold(fn
      path when path in ["/", ".", ""] -> nil
      path -> {Path.dirname(path), Path.dirname(path)}
    end)
    |> Enum.find_value(&Map.get(by_path, &1))
  end

  # An imported item is the record of what was imported. A scan may not touch
  # it.
  defp refresh_owner(%InboxItem{status: :imported}, _files), do: :skipped
  defp refresh_owner(%InboxItem{} = item, files), do: refresh_known(item, files)

  # An entirely unowned candidate is a release at the grain the walk proposes.
  # Leftovers in a *partly* owned folder go to the finest grain, since
  # something has already declared that folder to be more than one release.
  defp adopt(path, files, orphans, source) when files == orphans,
    do: create_item(path, orphans, source)

  defp adopt(_path, _files, orphans, source),
    do: Enum.map(orphans, &create_item(&1, [&1], source))

  # A known item's files can legitimately change. Its status is left alone,
  # and its source is never swapped: stored paths are relative to the item's
  # own source, so re-keying them would rewrite coordinates.
  defp refresh_known(%InboxItem{} = item, files) do
    item = Repo.preload(item, :source)
    stored_files = Enum.map(files, &stored_form(&1, item.source))

    if item.files == stored_files do
      :skipped
    else
      {:ok, item} = update_item(item, %{files: stored_files})

      if item.status == :pending do
        # The draft describes files that just moved under it. Say so; don't
        # re-seed over whatever the operator already decided.
        mark_draft_stale(item)
        probe_item_async(item)
      end

      :updated
    end
  end

  defp mark_draft_stale(%InboxItem{} = item) do
    update_draft_with(item, &Seed.restale/2)
    :ok
  end

  defp put_if(map, _key, _value, false), do: map
  defp put_if(map, key, value, _truthy), do: Map.put(map, key, value)

  # Always source-relative, so a source whose mount point changes is a
  # one-row edit and every queued item survives the move.
  defp stored_form(path, %Source{} = source) do
    {:ok, relative} = Library.relativize(source, path)
    relative
  end

  defp create_item(path, files, source) do
    %InboxItem{}
    |> InboxItem.changeset(%{
      path: stored_form(path, source),
      files: Enum.map(files, &stored_form(&1, source)),
      source_id: source.id
    })
    |> Repo.insert()
    |> case do
      {:ok, item} ->
        {:ok, _job} = probe_item_async(item)
        :created

      {:error, changeset} ->
        Logger.warning(fn -> "Couldn't add inbox item #{path}: #{inspect(changeset.errors)}" end)
        :skipped
    end
  end

  # Who owns what, read once per scan. `by_file` is the authority; `by_path`
  # only answers for files nothing has claimed. Keyed by resolved paths,
  # because the walk speaks absolutes.
  defp ledger do
    items = InboxItem |> Repo.all() |> Repo.preload(:source)

    %{
      # Every file the item holds, excluded ones included: forgetting one
      # would hand it an item of its own on the next scan.
      by_file:
        for(item <- items, file <- InboxItem.owned_disk_files(item), into: %{}, do: {file, item}),
      by_path: Map.new(items, &{InboxItem.disk_path(&1), &1})
    }
  end

  # Measured as the one recording it will become: durations add up into a
  # single book timeline, and tags are read off the first file the way
  # playback will encounter it.
  #
  # No more expensive than a single-file release of the same book: the
  # expensive part is decode-counting VBR mp3s, and forty files hold the same
  # hours of audio one file would.
  defp probe_recording(files) do
    case Scanner.probe_all(files) do
      {:ok, [first | _rest] = probes} ->
        %{probe: probe_map(probes), tags: tags_map(first.tags), issue: nil}

      {:error, reason} ->
        %{issue: "couldn't read the file: #{inspect(reason)}"}
    end
  end

  defp probe_map([first | _rest] = probes) do
    {chapters, marker_source} = Scanner.chapters(probes)

    %{
      "path" => first.path,
      "files" => length(probes),
      "size" => Enum.reduce(probes, 0, &(&1.size + &2)),
      "format" => first.format,
      "codec" => first.codec,
      "mime" => first.mime,
      "duration" => probes |> Scanner.total_duration() |> Decimal.to_string(),
      # The worst of them, not the first: one file that can't be seeked
      # accurately makes every seek past it inaccurate too.
      "seek_accuracy" => probes |> Enum.map(& &1.seek_accuracy) |> seek_accuracy(),
      "chapters" => length(chapters),
      "chapter_marker_source" => marker_source && to_string(marker_source),
      # The rows themselves, not just the count — the import form's chapter
      # editor states what the files carry without re-reading them.
      "chapter_list" =>
        Enum.map(chapters, fn chapter ->
          %{
            "time" => to_string(chapter.time),
            "title" => chapter.title,
            "title_source" => chapter.title_source && to_string(chapter.title_source)
          }
        end)
    }
  end

  defp seek_accuracy(accuracies) do
    if Enum.any?(accuracies, &(&1 == :approximate)), do: "approximate", else: "exact"
  end

  defp tags_map(tags), do: Tags.to_map(tags)
end
