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

  Each *immediate child* of the watched root is one candidate: a release
  folder (with all the audio beneath it) or a loose file. That's the \\*arr
  convention and it fits a downloads folder, which is the only kind of
  watched location that exists so far. Organized collections nested by
  author/series will want a different walk; that arrives with the
  watched-location registry.
  """

  use Boundary,
    deps: [Ambry, Ambry.Media],
    exports: [InboxItem]

  import Ecto.Query

  alias Ambry.Inbox.InboxItem
  alias Ambry.Inbox.RunDiscovery
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

    update_item(item, attrs)
  end

  def update_item(%InboxItem{} = item, attrs) do
    item
    |> InboxItem.changeset(attrs)
    |> Repo.update()
  end

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

  # One candidate per immediate child of the root: a release folder with all
  # the audio beneath it, or a loose file.
  defp candidates(root) do
    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.sort(NaturalOrder)
        |> Enum.map(&Path.join(root, &1))
        |> Enum.flat_map(&candidate/1)

      {:error, reason} ->
        Logger.warning(fn -> "Couldn't read watched location #{root}: #{inspect(reason)}" end)
        []
    end
  end

  defp candidate(path) do
    cond do
      File.dir?(path) ->
        case audio_files(path) do
          [] -> []
          files -> [{path, files}]
        end

      audio_file?(path) ->
        [{path, [path]}]

      true ->
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
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)
          if File.dir?(path), do: walk(path), else: [path]
        end)

      {:error, reason} ->
        Logger.warning(fn -> "Couldn't read #{dir}: #{inspect(reason)}" end)
        []
    end
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
