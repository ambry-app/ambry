defmodule Ambry.Inbox do
  @moduledoc """
  The curation queue every recording passes through before clients see it.

  **The inbox is the only road into the library.** Discovery finds candidates
  and records what they are; approval is what creates real records and touches
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
  """

  use Boundary,
    deps: [Ambry, Ambry.Library, Ambry.Media],
    # The draft tree is exported because it IS the import form's data model —
    # the form renders and edits it directly. Approval stays internal.
    exports: [InboxItem, {Draft, []}]

  import Ecto.Query

  alias Ambry.Inbox.Approval
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.Lookup
  alias Ambry.Inbox.Progress
  alias Ambry.Inbox.RunDiscovery
  alias Ambry.Inbox.RunMatch
  alias Ambry.Inbox.RunProbe
  alias Ambry.Library
  alias Ambry.Library.Location
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner
  alias Ambry.Repo

  require Logger

  @doc """
  Lists inbox items, newest first.

  Options: `:status`, `:filter` (matches the path), `:offset`, `:limit`.
  """
  def list_items(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    over_limit = limit + 1

    items =
      InboxItem
      |> filter_by_status(opts[:status])
      |> filter_by_ready(opts[:ready])
      |> filter_by_path(opts[:filter])
      |> order_by([i], desc: i.inserted_at, desc: i.id)
      |> offset(^Keyword.get(opts, :offset, 0))
      |> limit(^over_limit)
      |> preload(:location)
      |> Repo.all()

    items_to_return = Enum.slice(items, 0, limit)

    {items_to_return, items != items_to_return}
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
  How many pending items are fully settled and waiting on a click.

  Reads the denormalized flag rather than loading every draft — the whole
  reason it's stored.
  """
  def count_ready do
    InboxItem
    |> where([i], i.status == :pending and i.ready == true)
    |> Repo.aggregate(:count)
  end

  def get_item!(id), do: Repo.get!(InboxItem, id)

  def fetch_item(id), do: Repo.fetch(InboxItem, id)

  @no_counts %{created: 0, updated: 0, skipped: 0, unreachable: 0}

  @doc """
  Scans every watched location for candidates.

  Idempotent by design: an item's path is its identity, so rescanning updates
  the files of a known item rather than duplicating it, never resurrects a
  dismissed one, and never re-offers files the library already has.

  A location that can't be read doesn't fail the run — one unmounted NAS
  shouldn't stop the others from being scanned — but it is counted, because
  "found nothing" and "couldn't look" must not look the same to the operator.

  Returns `{:ok, %{created: n, updated: n, skipped: n, unreachable: n}}`.
  """
  def discover do
    case Library.watched_locations() do
      [] -> {:error, :no_watched_locations}
      locations -> {:ok, Enum.reduce(locations, @no_counts, &merge_counts(&2, discover_one(&1)))}
    end
  end

  @doc """
  Scans one location, or one bare path.

  The bare-path form is for ad-hoc scans and for exercising the walk itself;
  items it creates have no location, so approval can't know what custody they
  imply.
  """
  def discover(%Location{} = location) do
    with {:ok, counts} <- scan(location.path, location) do
      {:ok, _location} = Library.mark_scanned(location)
      {:ok, counts}
    end
  end

  def discover(root) when is_binary(root), do: scan(root, nil)

  defp discover_one(%Location{} = location) do
    case discover(location) do
      {:ok, counts} ->
        counts

      {:error, reason} ->
        Logger.warning(fn ->
          "Couldn't scan location #{location.name} (#{location.path}): #{inspect(reason)}"
        end)

        %{unreachable: 1}
    end
  end

  defp merge_counts(acc, counts), do: Map.merge(acc, counts, fn _key, a, b -> a + b end)

  defp scan(root, location) do
    if File.dir?(root) do
      known = known_paths()
      imported = imported_files()

      results =
        root
        |> candidates()
        |> Enum.map(&record_candidate(&1, known, imported, location))

      {:ok,
       %{
         created: Enum.count(results, &(&1 == :created)),
         updated: Enum.count(results, &(&1 == :updated)),
         skipped: Enum.count(results, &(&1 == :skipped)),
         unreachable: 0
       }}
    else
      {:error, :watched_location_missing}
    end
  end

  @doc """
  Records what an item's files actually are: direct-play facts plus whatever
  the file claims about itself.

  This never fails the item — an unreadable or unsupported candidate keeps
  its place in the queue with an `issue` explaining why, because the operator
  needs to see it to act on it.
  """
  def probe_item(%InboxItem{} = item) do
    attrs =
      case item.files do
        [file] -> probe_single(file, single_file: true)
        [] -> %{issue: "no audio files found"}
        [file | _rest] -> file |> probe_single() |> Map.put(:issue, multi_file_issue(item))
      end

    with {:ok, item} <- update_item(item, attrs) do
      # tags are what matching leans on, so it follows probing rather than
      # racing it
      {:ok, _job} = match_item_async(item)
      {:ok, item}
    end
  end

  def update_item(%InboxItem{} = item, attrs) do
    item
    |> InboxItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Proposes what an item is: which work, and which recording.

  Runs after probing, since the embedded tags it leans on come from there.
  Never fails the item — providers being unreachable means fewer candidates,
  not a broken queue entry.
  """
  def match_item(%InboxItem{} = item) do
    with {:ok, item} <- update_item(item, AutoMatch.match(item)) do
      # Staging the import is the point of matching — proposals nothing turns
      # into decisions are just data sitting in a column.
      prepare_draft(item)
    end
  end

  @doc """
  Proposes matches for one item in the background.
  """
  def match_item_async(%InboxItem{} = item) do
    %{inbox_item_id: item.id} |> RunMatch.new() |> Oban.insert()
  end

  @doc """
  Stages the import: turns what we found into a tree of decisions.

  Runs after matching, and is what the queue's Ready badge and the import
  form both read. Rebuilding is destructive to curation by definition, so it
  only ever happens when there is no draft yet — an operator's choices are
  not something a background job may overwrite.
  """
  def prepare_draft(%InboxItem{draft: nil} = item), do: rebuild_draft(item)
  def prepare_draft(%InboxItem{} = item), do: {:ok, item}

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
  What approval will do with this item's bytes, decided before it's asked.

  Placement can fail for reasons no amount of curation fixes — a downloads
  folder on a different NAS from its library root, a destination already
  occupied, no root registered at all. Those used to surface as an error at
  the moment the operator clicked approve. Working them out up front is what
  lets the form refuse to offer a button that fails, and it tells the
  operator *where the file is going* before they commit to it.

  Returns a map with `:custody`, a human `:summary`, and `:blocker` — nil when
  placement will work.
  """
  def destination_preflight(%InboxItem{} = item) do
    item = Repo.preload(item, :location)

    case item.location do
      %Location{kind: :downloads} = location -> downloads_preflight(item, location)
      %Location{kind: :library_root} -> adopt_preflight("It's already inside a library root.")
      %Location{kind: :external_collection} -> adopt_preflight("It's an external collection.")
      nil -> adopt_preflight("It came from an ad-hoc scan with no location.")
    end
  end

  defp adopt_preflight(why) do
    %{
      custody: :external,
      summary: "Referenced where it lies — #{why} Ambry will never move, rename or delete it.",
      blocker: nil
    }
  end

  defp downloads_preflight(item, location) do
    base = %{custody: :managed, blocker: nil, summary: nil}

    case chosen_root(item) do
      {:error, reason} ->
        %{base | blocker: describe_error(reason)}

      {:ok, root} ->
        %{
          base
          | summary: policy_summary(location.import_policy, root),
            blocker: hardlink_blocker(item, location, root)
        }
    end
  end

  # The root the draft settled on, not one derived from the location: inputs
  # and outputs are independent, so this is a decision rather than a lookup.
  defp chosen_root(%InboxItem{draft: %{destination: %{root_id: id}}}) when is_integer(id) do
    case Repo.get(Location, id) do
      %Location{kind: :library_root} = root -> {:ok, root}
      _other -> {:error, :no_library_root}
    end
  end

  defp chosen_root(_item), do: {:error, :no_library_root}

  defp policy_summary(:hardlink, root),
    do: "Hardlinked into #{root.path} — one copy of the bytes, the download keeps seeding."

  defp policy_summary(:copy, root),
    do: "Copied into #{root.path} — deliberately duplicating the bytes."

  defp policy_summary(:move, root),
    do: "Moved into #{root.path} — the downloads folder is left clean."

  defp policy_summary(_unset, root), do: "Placed into #{root.path}."

  # The refusal this whole phase exists for: a hardlink cannot cross a
  # filesystem, and silently copying instead is the storage doubling the
  # roadmap set out to eliminate. Worth knowing before the click, not after.
  defp hardlink_blocker(
         %InboxItem{files: [file | _rest]},
         %Location{import_policy: :hardlink},
         root
       ) do
    case Library.same_filesystem?(Path.dirname(file), root.path) do
      {:ok, true} -> nil
      {:ok, false} -> describe_error({:cross_filesystem, file, root.path})
      {:error, _reason} -> "Couldn't tell whether these are on the same filesystem."
    end
  end

  defp hardlink_blocker(_item, _location, _root), do: nil

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
  def approve_item(%InboxItem{} = item) do
    case Approval.approve(item) do
      {:ok, media} ->
        {:ok, media}

      {:error, reason} = error ->
        # A flash lasts one page load; these workers run `max_attempts: 1`,
        # so a discarded job lasts a day. Neither tells the operator anything
        # tomorrow, so the reason goes on the item itself.
        update_item(item, %{issue: describe_error(reason)})
        error
    end
  end

  @doc """
  Says what went wrong in a sentence the operator can act on.

  Shared between the flash shown at the time and the `issue` recorded on the
  item, so the row tomorrow says exactly what the toast said today.
  """
  def describe_error(:multi_file_unsupported),
    do:
      "Direct play handles single-file recordings for now — merge this one externally, or skip it."

  def describe_error(:no_published_date),
    do:
      "No publication date, and one can't be invented. Match a work, or tag the file with a date."

  def describe_error(:no_title),
    do: "Nothing here says what this is. Match a work, or tag the file with a title."

  def describe_error({:unreadable, _reason}),
    do: "Couldn't read the file — it may have moved or gone away since it was found."

  def describe_error({:source_missing, _path}), do: "The file has gone away since it was found."

  # The refusal this whole phase is built around, so it says what to do
  # rather than just what failed.
  def describe_error({:cross_filesystem, _source, _destination}),
    do:
      "This folder and its library root are on different filesystems, so the file can't be " <>
        "hardlinked. Point it at a root on the same disk, or set the location to copy or move."

  def describe_error({:destination_exists, path}),
    do: "Something is already at #{path}. Two recordings can't share one path."

  def describe_error(:no_library_root),
    do: "There's no library root to import into. Add one under Locations."

  def describe_error(:ambiguous_library_root),
    do: "There's more than one library root — say which one this folder imports into."

  def describe_error(:already_approved), do: "Already in the library."

  # The invariant, phrased for a human. It names the count rather than the
  # decisions because the form lists them properly — this is the flash you get
  # if you somehow reached approval from the queue.
  def describe_error({:unresolved, outstanding}) do
    count = length(outstanding)

    "#{count} thing#{if count > 1, do: "s"} still to settle before this can be imported. " <>
      "Open it to see what."
  end

  def describe_error(_reason), do: "Couldn't add this to the library."

  @doc """
  What is happening to each of these items in the background.
  """
  defdelegate progress(items), to: Progress, as: :statuses

  @doc """
  What a background job is doing to one item.
  """
  defdelegate job_status(item), to: Progress, as: :status

  @doc """
  Takes an item out of the queue without touching its files.

  Dismissals are remembered by path, so a rescan doesn't offer it again.
  """
  def dismiss_item(%InboxItem{} = item), do: update_item(item, %{status: :dismissed})

  def restore_item(%InboxItem{} = item), do: update_item(item, %{status: :pending})

  def delete_item(%InboxItem{} = item), do: Repo.delete(item)

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

  defp filter_by_ready(query, nil), do: query
  defp filter_by_ready(query, ready?), do: where(query, [i], i.ready == ^ready?)

  defp filter_by_path(query, blank) when blank in [nil, ""], do: query

  defp filter_by_path(query, filter), do: where(query, [i], ilike(i.path, ^"%#{filter}%"))

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

  # Deliberately strict. "Disc 02" and "3 of 5" are parts; "Gwendy's Button
  # Box 2" and "01 - The Restaurant at the End of the Universe" are their own
  # books, and a looser pattern (anything ending in a number) would swallow
  # them into one item.
  @part_folder ~r/^(disc|cd|part|vol|volume)\s*\.?\s*\d+$|^\d+\s*of\s*\d+$|\((disc|cd|part)\s*\d+\)$/i

  defp part_folder?(dir) do
    dir |> Path.basename() |> String.trim() |> then(&Regex.match?(@part_folder, &1))
  end

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

  defp record_candidate({path, files}, known, imported, location) do
    cond do
      Enum.any?(files, &MapSet.member?(imported, &1)) ->
        :skipped

      item = Map.get(known, path) ->
        refresh_known(item, files, location)

      true ->
        create_item(path, files, location)
    end
  end

  # A known item's files can legitimately change (a torrent finished, a file
  # was replaced). Its status is left alone: dismissed stays dismissed.
  #
  # An item found under a location adopts it if it had none — that's a fact
  # the scan just established, not a guess — but a location is never swapped
  # out from under an item that already has one.
  defp refresh_known(%InboxItem{} = item, files, location) do
    adopts_location? = is_nil(item.location_id) and not is_nil(location)

    changes =
      %{}
      |> put_if(:files, files, item.files != files)
      |> put_if(:location_id, adopts_location? && location.id, adopts_location?)

    if changes == %{} do
      :skipped
    else
      {:ok, item} = update_item(item, changes)

      if item.status == :pending and Map.has_key?(changes, :files) do
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

  defp create_item(path, files, location) do
    %InboxItem{}
    |> InboxItem.changeset(%{path: path, files: files, location_id: location && location.id})
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

  defp known_paths do
    InboxItem |> select([i], {i.path, i}) |> Repo.all() |> Map.new()
  end

  # Files the library already has, by either route: a direct-play track or a
  # legacy media's recorded source files.
  defp imported_files do
    track_paths = MediaTrack |> select([t], t.path) |> Repo.all()

    source_files =
      Media |> select([m], m.source_files) |> Repo.all() |> List.flatten()

    MapSet.new(track_paths ++ source_files)
  end

  defp probe_single(file, opts \\ []) do
    case Scanner.probe_file(file, opts) do
      {:ok, probe} ->
        %{probe: probe_map(probe), tags: tags_map(probe.tags), issue: nil}

      {:error, reason} ->
        %{issue: "couldn't read the file: #{inspect(reason)}"}
    end
  end

  defp multi_file_issue(%InboxItem{files: files}) do
    "#{length(files)} audio files — direct play handles single-file recordings for now; " <>
      "merge them externally or skip this one"
  end

  defp probe_map(probe) do
    %{
      "path" => probe.path,
      "size" => probe.size,
      "format" => probe.format,
      "codec" => probe.codec,
      "mime" => probe.mime,
      "duration" => probe.duration && Decimal.to_string(probe.duration),
      "seek_accuracy" => to_string(probe.seek_accuracy),
      "chapters" => length(probe.chapters)
    }
  end

  defp tags_map(tags) do
    %{
      "title" => tags.title,
      "book_title" => tags.book_title,
      "authors" => tags.authors,
      "narrators" => tags.narrators,
      "series" => tags.series,
      "series_number" => tags.series_number && Decimal.to_string(tags.series_number),
      "published" => tags.published && Date.to_iso8601(tags.published),
      "published_format" => tags.published_format && to_string(tags.published_format),
      "description" => tags.description,
      "publisher" => tags.publisher,
      "genre" => tags.genre,
      "language" => tags.language,
      "asin" => tags.asin,
      "has_cover_art" => tags.has_cover_art
    }
  end
end
