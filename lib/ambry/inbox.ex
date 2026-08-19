defmodule Ambry.Inbox do
  @moduledoc """
  The curation queue every recording passes through before clients see it.

  **The inbox is the only road into the library.** Discovery finds candidates
  and records what they are; import is what creates real records and touches
  files. Nothing here copies, links, moves, or organizes anything — an item
  references its files exactly where they landed.

  Why a queue rather than auto-import: Radarr can usually auto-import because
  its identification has a strong prior — it initiated the grab, or it's
  matching a conventionally-named release against a monitored library.
  Audiobooks have far weaker naming conventions and there's no wanted list to
  match against, so the uncertain case is the common case. Automation's job is
  to make confirmation one click, not to skip the human.

  ## Discovery shape

  A downloads folder does not say consistently where one release ends and
  the next begins, so the walk decides from what it finds. A folder holding
  audio directly *is* the release; a folder whose subfolders are plainly
  parts ("Disc 02", "3 of 5") is still one release; anything else is a
  container to look inside. Loose files at any level are their own release.

  That's measured against a real downloads tree rather than assumed — see
  `directory_candidate/1`.

  ## What a scan may change, and what it may not

  The walk runs hourly over folders the operator is working in, so what it
  is *allowed* to do matters more than what it finds. **Ownership decides,
  not the walk**: every file the queue already holds belongs to something,
  and the grouping the walk proposes is consulted only for files that belong
  to nothing.

  **The library owns nothing here.** Discovery hides no file on the grounds
  that a recording was once imported from it — a release the library already
  holds is exactly what an operator upgrading it to direct play wants to
  see, and the queue is the work list. That provenance is still read; it
  pre-fills the import form's replace decision instead of removing the row.

  A scan may therefore do exactly three things:

    * create items from files nothing owns,
    * give an unowned file to the item that owns the folder above it,
    * drop a file that is gone from its owner (which marks that item's draft
      stale, since the draft describes files that moved under it).

  It may never move a file from one item to another, and it never touches an
  imported item at all. That is what makes a split durable without a marker:
  once the operator says five folders are five releases, the files are owned,
  and re-walking the folder that holds them has nothing to say. It is a
  property of the construction rather than a rule the code has to remember —
  `record_candidate/3` groups by owner before it looks at anything else.
  """

  use Boundary,
    deps: [Ambry, Ambry.Library, Ambry.Media],
    # The draft tree is exported because it IS the import form's data model —
    # the form renders and edits it directly. Import stays internal.
    exports: [InboxItem, {Draft, []}]

  import Ecto.Query

  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Importer
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.Lookup
  alias Ambry.Inbox.Preflight
  alias Ambry.Inbox.Progress
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
  Lists inbox items, most recent first — of whatever "recent" means for the
  view being asked for.

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

  # The queue and the history are sorted by two different clocks, and using
  # one for both is what put a release imported this morning below one
  # imported last week.
  #
  # A **pending** item is waiting to be looked at, so the interesting moment
  # is when it was found: newest discoveries first.
  #
  # An **imported or ignored** item is a record of something the operator
  # did, so the interesting moment is when they did it — `updated_at`, which
  # is stamped by the status change itself. Discovery can't muddy it:
  # `record_candidate/4` skips a folder whose files are already imported, and
  # nothing else touches a settled row.
  defp newest_first(status) when status in [:imported, :ignored],
    do: [desc: :updated_at, desc: :id]

  defp newest_first(_pending_or_all), do: [desc: :inserted_at, desc: :id]

  @doc """
  How many items a list would have, under the filters it lists with.

  Takes the same options as `list_items/1` and ignores the paging ones, so
  the queue's "of 355" cannot drift from what the queue is showing.
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

  `count_by_status/0` sizes the tabs; this answers the question the operator
  opens the admin with, which is how much of the queue is *theirs*. "Pending"
  is three different errands wearing one word:

    * **ready** — the machine settled every decision and the only thing left
      is a human agreeing. Still work: nothing auto-publishes, so somebody
      has to look and press Add.
    * **decisions needed** — the machine couldn't settle something.
    * **unprepared** — no draft, so nobody has asked yet. This one is
      *waiting on the machine*, not on the operator, which is why the
      overview reports it beside the jobs rather than beside the other two.

  `issues` cuts across all three: an item can be ready and still carry the
  record of something that went wrong. It is counted, not subtracted.
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

    # The three buckets partition the pile, so the middle one is what the
    # other two leave behind rather than its own count — a query that asked
    # for it separately could disagree with the total by a row inserted
    # between the two, and a summary that doesn't add up is worse than a
    # coarse one.
    Map.put(
      counts,
      :decisions_needed,
      counts.pending - counts.ready - counts.unprepared
    )
  end

  @doc """
  How the providers have been answering, across the queue that's still open.

  One row per recorded outcome id — `hardcover` searched, `hardcover:details`
  hydrated — because those succeed and fail independently and rolling them
  together is exactly the mistake `Ambry.Metadata.Outcome` exists to prevent.

  Read from the items themselves rather than a log: an outcome is written
  where it is *used*, so this is the same evidence the import form shows,
  aggregated. It therefore describes the open queue, not all history — an
  imported item's troubles are over and don't belong in a health reading.
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

  def get_item!(id), do: Repo.get!(InboxItem, id)

  def fetch_item(id), do: Repo.fetch(InboxItem, id)

  @no_counts %{created: 0, updated: 0, skipped: 0, unreachable: 0}

  @doc """
  Scans every watched source for candidates.

  Idempotent by design: an item's path is its identity, so rescanning updates
  the files of a known item rather than duplicating it, never resurrects a
  ignored one, and never re-offers files the library already has.

  A source that can't be read doesn't fail the run — one unmounted NAS
  shouldn't stop the others from being scanned — but it is counted, because
  "found nothing" and "couldn't look" must not look the same to the operator.

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

  A source is the only way into the inbox. Scanning a bare path used to be
  possible and produced items with no source, which meant absolute stored
  paths, no placement default, and a whole second shape for every function
  that touches an item's files to handle. It was never reachable from the
  UI, so the exception bought nothing and cost that.
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

      results =
        source.path
        |> candidates()
        |> Enum.flat_map(&List.wrap(record_candidate(&1, ledger, source)))

      {:ok,
       %{
         created: Enum.count(results, &(&1 == :created)),
         updated: Enum.count(results, &(&1 == :updated)),
         skipped: Enum.count(results, &(&1 == :skipped)),
         unreachable: 0
       }}
    else
      {:error, :watched_source_missing}
    end
  end

  @doc """
  Records what an item's files actually are: direct-play facts plus whatever
  the file claims about itself.

  This never fails the item — an unreadable or unsupported candidate keeps
  its place in the queue with an `issue` explaining why, because the operator
  needs to see it to act on it.
  """
  def probe_item(%InboxItem{} = item, opts \\ []) do
    item = Repo.preload(item, :source)

    attrs =
      case item.files do
        [] -> %{issue: "no audio files found"}
        _files -> probe_recording(InboxItem.disk_files(item))
      end

    with {:ok, item} <- update_item(item, attrs) do
      # tags are what matching leans on, so it follows probing rather than
      # racing it
      {:ok, _job} = match_item_async(item, opts)
      {:ok, item}
    end
  end

  @doc """
  Re-reads one item from disk and re-asks every provider about it.

  The operator's "this is wrong, look at it again" action, and it has to mean
  all three of the things it sounds like it means. It replaced two buttons
  that between them did none of them:

    * **Re-read the files.** "Re-probe" ran ffprobe over the file list
      captured at *discovery*, so a release the operator had since fixed on
      disk — parts joined into one m4b, a stray file removed — probed exactly
      the same way forever. Only a full source scan refreshed the list.
    * **Ask the providers again, for real.** Provider answers are cached for
      thirty days, so re-matching re-derived identical records from identical
      cached responses and finished in milliseconds. The button could not
      find anything new by construction. This one passes `refresh: true` all
      the way down to `Metadata.Cache`.
    * **Actually run.** `RunMatch` is `unique` over a 60-second window, and
      Oban answers a uniqueness conflict with `{:ok, %{job | conflict?: true}}`
      — an insert that looks successful and does nothing. Since re-probing
      also enqueues a match, the two old buttons in sequence were *guaranteed*
      to no-op with a cheerful flash. Operator-initiated work opts out of
      uniqueness and reports what really happened.

  What it deliberately does NOT do is re-seed the draft: `prepare_draft/1`
  leaves an existing one alone, so new evidence appears in the form as
  un-ticked records rather than overwriting a decision. Curation outranks
  re-derivation — but the caller should say so, or "nothing happened" is the
  only available reading.
  """
  def rescan_item(%InboxItem{} = item) do
    with {:ok, item} <- refresh_files(item) do
      probe_item(item, refresh: true)
    end
  end

  @doc """
  Re-reads and re-queries one item in the background.

  Refused once the item is in the library: the probe rebuilds an untouched
  draft, and an imported item's draft is the record of what was imported.
  """
  def rescan_item_async(%InboxItem{status: :imported}), do: {:error, :already_imported}

  def rescan_item_async(%InboxItem{} = item) do
    %{inbox_item_id: item.id, refresh: true} |> RunProbe.new() |> Oban.insert()
  end

  # The files on disk, now, rather than the ones discovery happened to see.
  #
  # Left alone when the walk comes back empty: an NFS mount that is briefly
  # away must not be recorded as "this release has no audio in it", and a
  # genuinely empty folder is reported by probing instead. The walk speaks
  # absolutes; what gets stored is the source-relative form.
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

  def update_item(%InboxItem{} = item, attrs) do
    item
    |> InboxItem.changeset(attrs)
    |> Repo.update()
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

  Runs after probing, since the embedded tags it leans on come from there.
  Never fails the item — providers being unreachable means fewer candidates,
  not a broken queue entry.
  """
  def match_item(%InboxItem{} = item, opts \\ []) do
    with {:ok, item} <- update_item(item, AutoMatch.match(item, opts)) do
      # Staging the import is the point of matching — proposals nothing turns
      # into decisions are just data sitting in a column.
      #
      # A draft that already exists is **brought up to date**, not left alone:
      # matching has just replaced the evidence, and a retry that finally
      # reaches a provider buys nothing if the records it returns never reach
      # the form.
      #
      # Which update depends on whether a human has been here. An untouched
      # draft is rebuilt outright, because the retry's new record is not
      # *ticked* and re-deriving from the ticked set would ignore it. Once the
      # operator has decided anything, their draft is re-derived around them
      # instead — `resettle/2` keeps every curated choice.
      cond do
        is_nil(item.draft) ->
          rebuild_draft(item)

        Draft.curated?(item.draft) ->
          update_draft(item, item.draft |> Draft.Edit.resettle(item) |> dump())

        true ->
          rebuild_draft(item)
      end
    end
  end

  @doc """
  Which providers were asked about this item and couldn't answer.

  Not "found nothing" — that is an answer. This is the provider that was down,
  rate-limited or misconfigured, across every level: the work, the recording,
  and each person. `RunMatch` reads it to decide whether it is actually
  finished, because a match that reached three of four databases has not got
  what it set out to get.
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

  A refreshing run opts out of `RunMatch`'s uniqueness window. That window
  exists to collapse the storm of duplicate jobs a rescan of a whole source
  produces; an operator who clicked a button meant it, and silently dropping
  their job is how "look for matches again" came to do nothing at all.
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

  **A draft is a snapshot of the library taken when the item was matched**, and
  import executes it exactly. So two queued items implying the same new
  person, identity or series each created their own: measured on a real batch
  of seven, Em Grosland narrates both Monk & Robot books and arrived as two
  People and two Narrators, and "Monk and Robot" arrived as two Series. Books
  are the same bug waiting for two recordings of one work — the split library
  the whole work-identity design exists to prevent.

  The seeder's rule was never wrong; it ran against stale facts. So this
  re-points references rather than deciding: `Seed.relink/2` turns a credit or
  series that meant to *create* something into a *link* when exactly one thing
  of that name now exists, and changes nothing else. The affected credit
  visibly becomes "link the existing Em Grosland" **before** the operator
  imports it, so import still executes only what the form showed.

  Deliberately narrower than a re-seed, which would also re-open questions the
  operator had already answered — see `Seed.relink/2`.
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

  # A cheap candidate filter over the stored draft, not a precise one — a
  # false positive costs an idempotent re-derivation that changes nothing,
  # while scanning every pending item would cost a full rebuild each on a
  # queue that is hundreds long during a cold start.
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

  # Never fatal: the import succeeded, and a sibling that won't re-derive is a
  # stale proposal to fix on the form, not a reason to fail the import that
  # already committed.
  defp refresh_draft(%InboxItem{} = item) do
    case update_draft(item, item.draft |> Seed.relink(item) |> dump()) do
      {:ok, _item} ->
        :ok

      {:error, _changeset} ->
        Logger.warning(fn -> "Inbox: couldn't refresh draft for item #{item.id}" end)
        :ok
    end
  end

  @doc """
  Stages the import: turns what we found into a tree of decisions.

  Runs after matching, and is what the queue's Ready badge and the import
  form both read. Rebuilding is destructive to curation by definition, so it
  only ever happens when there is no draft yet — an operator's choices are
  not something a background job may overwrite.
  """
  def prepare_draft(%InboxItem{draft: nil} = item), do: rebuild_draft(item)

  # An imported item's draft is the record of what was imported; nothing may
  # touch it, healing included.
  def prepare_draft(%InboxItem{status: :imported} = item), do: {:ok, item}

  def prepare_draft(%InboxItem{} = item) do
    fresh =
      item.draft
      |> refresh_destination(item)
      |> refresh_replacement(item)

    if fresh == item.draft,
      do: {:ok, item},
      else: item |> InboxItem.put_draft(dump(fresh)) |> Repo.update()
  end

  # A decision the operator has not answered is a *default*, and a default
  # frozen at match time is the wrong default the moment anything it was
  # derived from changes. A draft is written once and then only read, so
  # nothing would ever revise it: import the first of three hundred queued
  # releases, correct the policy while you're there, and the other two
  # hundred and ninety-nine would keep proposing the old one forever.
  #
  # So the unanswered ones are re-derived here, on every prepare. The
  # answered ones are never touched — that is the entire distinction the
  # `chosen` and `curated` flags exist to draw.
  defp refresh_destination(%Draft{} = draft, item) do
    %{draft | destination: Seed.redefault(draft.destination || %Destination{}, item)}
  end

  defp refresh_replacement(%Draft{} = draft, item) do
    %{draft | replacement: Seed.repropose(draft.replacement || %Replacement{}, item)}
  end

  @doc """
  Throws away the staged import and seeds a fresh one from current evidence.

  The operator's escape hatch when a draft was built against the wrong match
  and editing it would be more work than starting over. Never automatic.
  """
  def rebuild_draft(%InboxItem{} = item) do
    item
    |> InboxItem.put_draft(item |> Seed.build() |> dump())
    |> Repo.update()
  end

  @doc """
  Saves operator edits to the staged import.

  Every save recomputes readiness, so the queue can never claim an item is
  importable when its draft says otherwise.
  """
  def update_draft(%InboxItem{status: :imported}, _attrs), do: {:error, :already_imported}

  def update_draft(%InboxItem{} = item, attrs) do
    item
    |> InboxItem.put_draft(attrs)
    |> Repo.update()
  end

  @doc """
  How a provider record is referred to: its provider and that provider's id.
  """
  defdelegate record_ref(record), to: AutoMatch, as: :ref

  @doc """
  Scoring hints from a library record's own fields — what lets the edit
  forms rank provider records exactly the way matching ranks them against
  an item's tags. (The scoring itself is `score_records/3`; its true home
  is the metadata layer, and it lives here only because moving the
  battle-tested scorer wholesale wasn't worth the risk the day the edit
  forms started needing it.)
  """
  defdelegate form_hints(fields), to: AutoMatch

  @doc """
  What this item's tags and release name say it is — the same hints matching
  searched with.

  The import form seeds its search boxes from these, so a re-search starts
  from what was actually looked for rather than from nothing.
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

  Placement can fail for reasons no amount of curation fixes — a downloads
  folder on a different NAS from its library root, a destination already
  occupied, no root registered at all. Those used to surface as an error at
  the moment the operator clicked import. Working them out up front is what
  lets the form refuse to offer a button that fails, and it tells the
  operator *where the file is going* before they commit to it.

  Returns a map with a human `:summary` and a `:blocker` — nil when placement
  will work.
  """
  def destination_preflight(%InboxItem{} = item) do
    item = Repo.preload(item, :source)

    case chosen_root(item) do
      {:error, reason} -> %{blocker: describe_error(reason)}
      {:ok, root} -> %{blocker: hardlink_blocker(item, chosen_policy(item), root)}
    end
  end

  # The draft's choice, or the default the seed put there. There is no
  # source-level fallback any more: how the files come in is a fact about
  # the pairing, so with no root settled there is nothing to fall back to.
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
  # different fixes — the picker is sitting right above one of the two
  # messages, and it used to be told there was nothing to pick.
  defp chosen_root(_item) do
    case Library.list_roots() do
      [] -> {:error, :no_library_root}
      _some -> {:error, :ambiguous_library_root}
    end
  end

  # The refusal this whole phase exists for: a hardlink cannot cross a
  # filesystem, and silently copying instead is the storage doubling the
  # roadmap set out to eliminate. Worth knowing before the click, not after.
  # Symlink deliberately gets no blocker: it has no precondition to fail.
  defp hardlink_blocker(item, :hardlink, root) do
    case hardlinkable(item, root) do
      {:ok, true} -> nil
      {:ok, false} -> describe_error({:cross_filesystem, first_file(item), root.path})
      {:error, _reason} -> "Couldn't tell whether these are on the same filesystem."
    end
  end

  defp hardlink_blocker(_item, _policy, _root), do: nil

  # Asked of the item's real files rather than its source's path: the
  # default is derived from the pairing, but the answer that gates a
  # placement has to be about the bytes being placed.
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

  Creates the whole entity graph in one transaction — book, credits, series,
  the recording and its tracks — with the files referenced where they lie.
  Nothing is published: the recording is created `pending`.
  """
  def import_item(%InboxItem{} = item) do
    case Importer.import_item(item) do
      {:ok, media} ->
        # Bookkeeping, and it runs after the records are committed. Neither
        # of these may fail the import — the library already holds the
        # recording, so a job reported as failed would be a lie the operator
        # acts on — and neither may skip the other, so they are guarded
        # separately. `Placement.finalize/1` states the same rule one call
        # further in, for the same reason.
        after_commit(item, "remember the placement", fn -> remember_placement(item) end)
        after_commit(item, "relink sibling drafts", fn -> refresh_siblings(item) end)
        {:ok, media}

      {:error, reason} = error ->
        # A flash lasts one page load; these workers run `max_attempts: 1`,
        # so a discarded job lasts a day. Neither tells the operator anything
        # tomorrow, so the reason goes on the item itself.
        update_item(item, %{issue: describe_error(reason)})
        error
    end
  end

  # Work that happens once the import has committed is untidy when it
  # fails, not broken. `RunImport` is `max_attempts: 1`, so a raise here
  # would discard the job for a release the library actually has, and take
  # the *other* piece of bookkeeping down with it.
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

  # What the next import from this source should propose is what this one
  # did. Remembered after the fact rather than when the operator picked: a
  # choice made on a release that then failed to place is not what the
  # source does.
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

  # The default just moved, and every queued item that was following the old
  # one is now proposing the wrong thing. Opening each would fix it, but the
  # queue's Ready badge reads a stored column — so nothing would look
  # different until the operator opened all three hundred, which is the
  # opposite of what remembering a choice is for.
  #
  # Only runs when the memory actually changed, which after the first import
  # from a source is almost never.
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

  Placing a release is the longest thing the inbox does — every file
  re-probed, then every byte copied — and running it inside the form meant
  the operator watched a spinner they could kill by closing the tab. The job
  belongs to the server; the row says what is happening to it.

  Refuses an item that is already in the library, since the queued job would
  only rediscover that a minute later and write it onto the row as an issue.

  ## The pre-flight

  Also refuses, once, when the draft would create something the library may
  already have, returning `{:error, {:collisions, findings}}` — see
  `Ambry.Inbox.Preflight`. A draft is a snapshot of a library that keeps
  moving, and this is the last moment anything is asked before rows are
  created.

  It asks again rather than trusting a flag: pass the findings back as
  `:acknowledged` and the import proceeds only if the library still says
  exactly that. Anything that appeared while the operator was reading is a
  collision they were never shown, so it stops them again.
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

  Shared between the flash shown at the time and the `issue` recorded on the
  item, so the row tomorrow says exactly what the toast said today.
  """

  def describe_error(:no_published_date),
    do:
      "No publication date, and one can't be invented. Match a book, or tag the file with a date."

  def describe_error(:no_title),
    do: "Nothing here says what this is. Match a book, or tag the file with a title."

  def describe_error({:unreadable, _reason}),
    do: "Couldn't read the file. It may have moved since it was found."

  def describe_error({:source_missing, _path}), do: "The file has gone away since it was found."

  # The refusal this whole phase is built around, so it says what to do
  # rather than just what failed.
  def describe_error({:cross_filesystem, _source, _destination}),
    do:
      "These files and the library root are on different filesystems, so they can't be " <>
        "hardlinked. Choose copy or move, or a root on the same disk."

  # Occupied by a recording is now a *bug*, not a curation problem. Every
  # recording's name carries its own token, so two of them cannot render to
  # one path however the operator curates them — if this happens, two records
  # claim one file and no amount of editing metadata will fix it.
  #
  # Occupied by a file no record references is the ordinary case that remains:
  # an interrupted import's copy landed and its transaction rolled back, which
  # is placement's documented worst case. The two need opposite advice.
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

  # The invariant, phrased for a human. It names the count rather than the
  # decisions because the form lists them properly — this is the flash you get
  # if you somehow reached import from the queue.
  def describe_error({:unresolved, outstanding}) do
    count = length(outstanding)

    "#{count} thing#{if count > 1, do: "s"} still to settle before this can be imported. " <>
      "Open it to see what."
  end

  # What the queue's own import button says. The findings themselves need the
  # form, which is where the answer ("link that book instead") can be given,
  # so this counts them and sends the operator there.
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

  One query for a page of items, like `progress/1` — the queue renders an
  imported row as the audiobook it produced, and a query per row is how a
  list page gets slow quietly.

  An imported item can have no audiobook: deleting one nilifies the link
  rather than taking the record of the import with it, so a missing key here
  is a fact the row has to be able to state.
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

  def delete_item(%InboxItem{} = item), do: Repo.delete(item)

  @doc """
  Splits a wrongly-grouped item into several, `by: :folder` or `by: :file`.

  The grouping heuristic is folder-based — a folder holding audio directly is
  one release, and a folder of "1 of 5" subfolders is one release in parts —
  and it has two known failures, at two different grains. Two unrelated
  single-file books can share a folder; and a set can be *five recordings*
  rather than one in five parts, which is exactly what a GraphicAudio release
  is. The operator is the one who can tell, so the split asks them at which
  grain it was wrong:

    * `:folder` — one item per folder the files live in. The five parts of
      The Way of Kings become five items of seven files each, each free to
      take its own part number in a set.
    * `:file` — one item per file, the finest grain there is, for the folder
      that was never one release at all.

  Children are inserted in the shape discovery gives an item of that grain
  (`path` = the folder, or the file), with a fresh probe and the match that
  follows it queued, because the parent's probe, tags and matches described
  its first file only.

  A split survives rescans without any marker: discovery respects a finer
  partition that already exists — see `record_candidate/4`.

  Refused once imported (the item is the record of what was imported), below
  two files, and when the chosen grain wouldn't actually divide anything —
  splitting a single-folder item by folder is a no-op, and doing it silently
  would delete and recreate the item for nothing.
  """
  def split_item(item, by \\ :file)

  def split_item(%InboxItem{status: :imported}, _by), do: {:error, :already_imported}

  def split_item(%InboxItem{files: files}, _by) when length(files) < 2,
    do: {:error, :not_multi_file}

  def split_item(%InboxItem{} = item, by) do
    case split_groups(item, by) do
      [_one] -> {:error, :not_divisible}
      groups -> replace_with_children(item, groups)
    end
  end

  defp replace_with_children(%InboxItem{} = item, groups) do
    Repo.transact(fn ->
      with {:ok, _parent} <- Repo.delete(item),
           {:ok, children} <- insert_children(item, groups) do
        # In the transaction on purpose: a job for a child that didn't get
        # created must not exist either.
        Enum.each(children, fn child -> {:ok, _job} = probe_item_async(child) end)
        {:ok, children}
      end
    end)
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

  # Files keep the order they were discovered in *within* a group — that is
  # playing order, and re-sorting it here would quietly reorder a book.
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

  # Matches the path AND what the draft says the item is, which is the whole
  # reason the column exists: an item whose folder is
  # `01 Angels and Demons.m4b` is findable by "Dan Brown".
  #
  # It also stops operator-typed `%` and `_` being live wildcards. The
  # `ILIKE '%…%'` this replaces interpolated the phrase straight into a
  # pattern, so typing a percent sign matched the entire queue. There is no
  # pattern left to escape now — the phrase is a parameter to
  # `plainto_tsquery`, which reads punctuation as punctuation.
  defp filter_by_search(query, blank) when blank in [nil, ""], do: query

  defp filter_by_search(query, filter) do
    if String.trim(filter) == "" do
      query
    else
      # No emptiness guard: a phrase that produced no lexemes matches nothing,
      # and `@@ NULL` being NULL rather than false is exactly that. A guard
      # here would mean typing a word the stemmer drops — `don`, `will`,
      # `can`, all in English's stop list — showed the whole queue.
      where(query, [i], fragment("? @@ ambry_tsquery(?, 'all', true)", i.search_vector, ^filter))
    end
  end

  # An issue cuts across the three buckets rather than replacing them (see
  # `queue_summary/0`), so it narrows whatever list is already showing
  # instead of being a status of its own.
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
  # not answer consistently. Measured against the real thing, three shapes
  # exist and the rule has to tell them apart:
  #
  #   Dan Brown - Origin/*.mp3          one book, audio sitting right there
  #   Discworld/<43 titles>/*.mp3       a whole series in one folder
  #   The Way of Kings/{1 of 5, ...}    one book split across subfolders
  #
  # Taking every immediate child as a release turns Discworld into a single
  # 1707-file item; recursing to the deepest audio-bearing folder shatters
  # The Way of Kings into five. So: audio in hand means this is the release,
  # subfolders that are plainly *parts* keep the parent as the release, and
  # anything else is a container worth looking inside.
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

  # The shape lives in `ReleaseName` because two callers read it: this walk,
  # deciding a folder of parts is one release, and an item named after one of
  # those folders, which has to say what it is a part *of*.
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

  # Walked by hand rather than with `Path.wildcard/2`: release folders are
  # full of glob metacharacters ("The Way of Kings [M4B]" is a character
  # class), and a folder whose name happens to contain brackets must not
  # silently go missing.
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
  # **Ownership decides, not the walk.** Every file the queue already holds
  # belongs to something, and a scan's only job is to find the ones that
  # don't. Which release a *known* file belongs to is settled — the operator
  # may have split its folder into five, or into thirty-five, and no amount
  # of re-walking that folder is allowed to have an opinion about it.
  #
  # That is the whole of the safety property, and it is structural: this
  # groups the candidate's files by who owns them *before* looking at
  # anything, so the grouping the walk proposes is only ever consulted for
  # files with no owner at all.
  #
  # **The library is not an owner.** Discovery used to skip any file a
  # recording had been imported from, which made a release the library
  # already holds invisible — and invisible is exactly the wrong answer for
  # the operator upgrading a legacy recording to direct play, because that
  # release is the work. The provenance is still read, one step further on:
  # it pre-fills the import form's replace decision (`Ambry.Media.imported_from/1`),
  # demoted from a filter to a suggestion the operator confirms.
  defp record_candidate({path, files}, ledger, source) do
    files
    |> Enum.group_by(&owner_of(&1, ledger))
    |> Enum.flat_map(fn
      {nil, orphans} -> List.wrap(adopt(path, files, orphans, source))
      {%InboxItem{} = item, theirs} -> [refresh_owner(item, theirs)]
    end)
  end

  # A file's owner, in the order that decides it: the item that already lists
  # it, then the nearest item *above* it — which is how a file that appears
  # in a known release folder joins that release rather than becoming an item
  # of its own.
  defp owner_of(file, ledger) do
    cond do
      item = ledger.by_file[file] -> item
      item = nearest_owner(file, ledger.by_path) -> item
      true -> nil
    end
  end

  # Walked up from the file rather than searched across every item: depth is
  # single digits, the item list is hundreds, and this runs per file.
  defp nearest_owner(file, by_path) do
    file
    |> Stream.unfold(fn
      path when path in ["/", ".", ""] -> nil
      path -> {Path.dirname(path), Path.dirname(path)}
    end)
    |> Enum.find_value(&Map.get(by_path, &1))
  end

  # An imported item is the record of what was imported; its source files may
  # not even be where they were. Nothing about a scan may touch it.
  defp refresh_owner(%InboxItem{status: :imported}, _files), do: :skipped
  defp refresh_owner(%InboxItem{} = item, files), do: refresh_known(item, files)

  # Nobody owns these. A candidate that is entirely unowned is a release, at
  # the grain the walk proposes; anything left over in a folder that is
  # *partly* owned goes to the finest grain there is, because something has
  # already declared that folder to be more than one release.
  defp adopt(path, files, orphans, source) when files == orphans,
    do: create_item(path, orphans, source)

  defp adopt(_path, _files, orphans, source),
    do: Enum.map(orphans, &create_item(&1, [&1], source))

  # A known item's files can legitimately change (a torrent finished, a file
  # was replaced). Its status is left alone: ignored stays ignored, and its
  # source is never swapped out from under it — the item's own source is
  # what its stored paths are relative to, so re-keying them to whichever
  # source happened to walk over them would silently rewrite coordinates.
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

  defp mark_draft_stale(%InboxItem{draft: nil}), do: :ok

  defp mark_draft_stale(%InboxItem{} = item) do
    item |> InboxItem.put_draft(item.draft |> Seed.restale(item) |> dump()) |> Repo.update()
    :ok
  end

  defp put_if(map, _key, _value, false), do: map
  defp put_if(map, key, value, _truthy), do: Map.put(map, key, value)

  # The stored form of an absolute path the walk produced. Always
  # source-relative: a source whose mount point changes is then a one-row
  # edit, and every queued item survives the move.
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

  # Who owns what, read once per scan.
  #
  # `by_file` is the authority — an item's own list of files — and `by_path`
  # only answers for files nothing has claimed yet, so a new file in a known
  # folder joins the item that holds the folder.
  # The walk speaks absolutes, so the ledger's keys are the items' resolved
  # paths — the stored source-relative forms never meet a scanned path
  # directly.
  defp ledger do
    items = InboxItem |> Repo.all() |> Repo.preload(:source)

    %{
      by_file:
        for(item <- items, file <- InboxItem.disk_files(item), into: %{}, do: {file, item}),
      by_path: Map.new(items, &{InboxItem.disk_path(&1), &1})
    }
  end

  # The whole release, measured as the one recording it will become: the
  # durations add up into a single book timeline, and the tags are read off
  # the first file the way playback will encounter it.
  #
  # This costs no more than a single-file release of the same book — the
  # expensive part is decode-counting VBR mp3s, and forty files hold the same
  # fourteen hours of audio one file would.
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
