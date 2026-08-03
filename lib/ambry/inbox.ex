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
    deps: [Ambry, Ambry.Media],
    exports: [InboxItem]

  import Ecto.Query

  alias Ambry.Inbox.Approval
  alias Ambry.Inbox.AutoMatch
  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunDiscovery
  alias Ambry.Inbox.RunMatch
  alias Ambry.Inbox.RunProbe
  alias Ambry.Media.Media
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.Scanner
  alias Ambry.Paths
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
      |> filter_by_path(opts[:filter])
      |> order_by([i], desc: i.inserted_at, desc: i.id)
      |> offset(^Keyword.get(opts, :offset, 0))
      |> limit(^over_limit)
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

  def get_item!(id), do: Repo.get!(InboxItem, id)

  def fetch_item(id), do: Repo.fetch(InboxItem, id)

  @doc """
  Scans the watched location for candidates.

  Idempotent by design: an item's path is its identity, so rescanning updates
  the files of a known item rather than duplicating it, never resurrects a
  dismissed one, and never re-offers files the library already has.

  Returns `{:ok, %{created: n, updated: n, skipped: n}}`.
  """
  def discover do
    case Paths.local_import_path() do
      nil -> {:error, :no_watched_location}
      root -> discover(root)
    end
  end

  def discover(root) do
    if File.dir?(root) do
      known = known_paths()
      imported = imported_files()

      results =
        root
        |> candidates()
        |> Enum.map(&record_candidate(&1, known, imported))

      {:ok,
       %{
         created: Enum.count(results, &(&1 == :created)),
         updated: Enum.count(results, &(&1 == :updated)),
         skipped: Enum.count(results, &(&1 == :skipped))
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
        [file] -> probe_single(file)
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
    update_item(item, AutoMatch.match(item))
  end

  @doc """
  Proposes matches for one item in the background.
  """
  def match_item_async(%InboxItem{} = item) do
    %{inbox_item_id: item.id} |> RunMatch.new() |> Oban.insert()
  end

  @doc """
  Approves an item into the library.

  Creates the whole entity graph in one transaction — book, credits, series,
  the recording and its tracks — with the files referenced where they lie.
  Nothing is published: the recording is created `pending`.
  """
  defdelegate approve_item(item), to: Approval, as: :approve

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

  defp record_candidate({path, files}, known, imported) do
    cond do
      Enum.any?(files, &MapSet.member?(imported, &1)) ->
        :skipped

      item = Map.get(known, path) ->
        refresh_known(item, files)

      true ->
        create_item(path, files)
    end
  end

  # A known item's files can legitimately change (a torrent finished, a file
  # was replaced). Its status is left alone: dismissed stays dismissed.
  defp refresh_known(%InboxItem{} = item, files) do
    if item.files == files do
      :skipped
    else
      {:ok, item} = update_item(item, %{files: files})
      if item.status == :pending, do: probe_item_async(item)
      :updated
    end
  end

  defp create_item(path, files) do
    %InboxItem{}
    |> InboxItem.changeset(%{path: path, files: files})
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

  defp probe_single(file) do
    case Scanner.probe_file(file) do
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
