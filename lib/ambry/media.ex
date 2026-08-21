defmodule Ambry.Media do
  @moduledoc """
  Functions for dealing with Media.
  """

  use Boundary,
    deps: [Ambry, Ambry.Library],
    exports: [
      Audit,
      Chapters.Merge,
      Editions,
      Editions.Edition,
      Media,
      Media.Chapter,
      MediaFlat,
      MediaNarrator,
      MediaTrack,
      RecordingGroup,
      RecordingGroupForm,
      Scanner,
      Scanner.Tags,
      PubSub.MediaCreated,
      PubSub.MediaDeleted,
      PubSub.MediaUpdated,
      PubSub.RecordingGroupCreated,
      PubSub.RecordingGroupDeleted,
      PubSub.RecordingGroupUpdated
    ]

  import Ambry.Utils
  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Library
  alias Ambry.Media.Audit
  alias Ambry.Media.Media
  alias Ambry.Media.MediaFlat
  alias Ambry.Media.MediaTrack
  alias Ambry.Media.PubSub.MediaCreated
  alias Ambry.Media.PubSub.MediaDeleted
  alias Ambry.Media.PubSub.MediaUpdated
  alias Ambry.Media.PubSub.RecordingGroupCreated
  alias Ambry.Media.PubSub.RecordingGroupDeleted
  alias Ambry.Media.PubSub.RecordingGroupUpdated
  alias Ambry.Media.RecordingGroup
  alias Ambry.Media.RecordingGroupForm
  alias Ambry.Media.RunOrganize
  alias Ambry.Media.RunPublishPending
  alias Ambry.Paths
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search.Query
  alias Ambry.Settings
  alias Ambry.Thumbnails
  alias Ambry.Thumbnails.GenerateThumbnails

  defdelegate get_media_file_details(media), to: Audit
  defdelegate orphaned_files_audit(), to: Audit

  @doc """
  Brings a recording's files back in line with the naming template.

  Asynchronous because it touches the filesystem, and safe to call after any
  edit: a recording that is already where it belongs, or that lives in the
  legacy uploads tree rather than a library root, is a no-op.
  """
  def organize_async(%Media{id: id}), do: enqueue_organize(%{"media_id" => id})

  @doc """
  The same, for every recording of a book.

  A book's title, primary author and primary series all appear in the path of
  every recording of it, so editing the book moves its files, not just its
  own page.
  """
  def organize_book_async(book_id), do: enqueue_organize(%{"book_id" => book_id})

  defp enqueue_organize(args), do: args |> RunOrganize.new() |> Oban.insert()

  @doc """
  Publishes every direct-play recording that's only waiting on the switch.

  The switch holds recordings back until the fleet can play them, so turning
  it on has to release the ones that piled up behind it — otherwise the
  operator would have to open and re-save every recording the inbox ever
  approved.

  Deliberately narrow. A recording qualifies only if it is `pending`, has
  tracks, has **no** legacy transcoded paths, and isn't currently missing.
  That last pair matters: a legacy recording sitting in `pending` has no
  tracks to publish and this switch is not what it is waiting on, and
  publishing a recording whose files have vanished would hand clients
  something unplayable.
  """
  def publish_pending_direct_play do
    Media
    |> where([m], m.status == :pending and is_nil(m.missing_since))
    |> where([m], is_nil(m.mp4_path) and is_nil(m.hls_path) and is_nil(m.mpd_path))
    |> join(:inner, [m], t in MediaTrack, on: t.media_id == m.id)
    |> distinct(true)
    |> preload(:media_tracks)
    |> Repo.all()
    |> Enum.reduce(%{published: 0, failed: 0}, fn media, counts ->
      case update_media(media, %{status: :ready}) do
        {:ok, _media} -> Map.update!(counts, :published, &(&1 + 1))
        {:error, _changeset} -> Map.update!(counts, :failed, &(&1 + 1))
      end
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  The same, in the background — the switch shouldn't block on a large library.
  """
  def publish_pending_direct_play_async do
    %{} |> RunPublishPending.new() |> Oban.insert()
  end

  @doc """
  Returns a limited list of media and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_media()
      {[%MediaFlat{}, ...], true}

  """
  def list_media(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ [asc: :book]) do
    over_limit = limit + 1

    media =
      offset
      |> MediaFlat.paginate(over_limit)
      |> MediaFlat.filter(filters)
      |> MediaFlat.order(order)
      |> Repo.all()

    media_to_return = Enum.slice(media, 0, limit)

    {media_to_return, media != media_to_return}
  end

  @doc """
  Recordings matching what somebody typed into a picker, as rich options.

  Reaches any audiobook in the library by title, book, author, narrator,
  series or universe — the same search the index offers, without its
  pagination. With nothing typed, the first page by book.

  Ranked, which it has to be spelled out to be. This asked `Query.ids/3`
  once, and that function drops the `ORDER BY` deliberately — it is the admin
  list filter's, where the operator has already chosen a sort. A picker has
  not chosen one: ranking *is* the answer. Sorting the candidates
  alphabetically and then taking ten meant "mars" showed the ten
  alphabetically-first of 69 candidate books, and Red Mars, ranked first, was
  not among them.

  The recordings of one book stay together and in part order, since which
  book it is decides the match and the parts are a menu within it.
  """
  def search_media(phrase, limit) do
    case String.trim(phrase || "") do
      "" ->
        # Nothing typed: the first page, by book. There is no ranking to keep.
        MediaFlat
        |> order_by([m], asc: m.book, asc: m.part_number, asc: m.id)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.map(&media_option/1)

      typed ->
        ranked_book_ids =
          Query.ranked_ids(typed, limit, joiner: :narrowing, partial: true, types: [:book])

        rank = ranked_book_ids |> Enum.with_index() |> Map.new()

        MediaFlat
        |> where([m], m.book_id in ^ranked_book_ids)
        |> Repo.all()
        |> Enum.sort_by(&{Map.fetch!(rank, &1.book_id), &1.part_number || 0, &1.id})
        |> Enum.take(limit)
        |> Enum.map(&media_option/1)
    end
  end

  @doc """
  Every audiobook of one book, as picker options.

  What a set may hold. A set belongs to a book the way its members do, so its
  member picker offers that book's audiobooks and nothing else — and there
  are two or three of them, which is a menu rather than a search. No phrase
  and no limit: the caller is a drop-down and wants the lot.
  """
  def book_media_options(nil), do: []

  def book_media_options(book_id) do
    MediaFlat
    |> where([m], m.book_id == ^book_id)
    |> order_by([m], asc: m.part_number, asc: m.id)
    |> Repo.all()
    |> Enum.map(&media_option/1)
  end

  @doc """
  One recording as a picker option, or nil.

  What lets a picker name the recording it is already holding — the preloaded
  list this replaced was answering that silently, since the id was in it.

  Built off the flat view rather than the record so that every surface
  describes a recording the same way: its display title, its cover, and what
  actually tells two recordings of one book apart.
  """
  def media_option(blank) when blank in [nil, ""], do: nil

  def media_option(%MediaFlat{} = media) do
    %{
      id: media.id,
      label: media_option_label(media),
      # Where it sits, muted, on the label's own line: the detail line below
      # is already carrying five facts, and the series is the one that tells
      # two same-titled records apart at a glance.
      trailer: series_credit(media.series),
      # What it is *found* by, which its label isn't: the label composes a
      # part suffix onto the title, and no column holds "A Court of Thorns
      # and Roses (Part 1 of 2)". A picker reopened on a set member searched
      # for exactly that and reported "No matches" about the recording it was
      # already holding.
      query: media.title || media.book,
      image: media.thumbnail,
      detail: media_option_detail(media)
    }
  end

  def media_option(id), do: MediaFlat |> Repo.get(id) |> media_option()

  # The book's title unless this recording overrides it, plus its place in a
  # set — the composition `Media.display_title/1` makes, off the view's own
  # columns.
  defp media_option_label(%MediaFlat{} = media) do
    title = media.title || media.book

    case Media.part_label(media) do
      nil -> title
      part -> "#{title} (#{part})"
    end
  end

  # The credit stack on one line, in the joins the vocabulary uses, then the
  # facts that separate two readings of one book. "Streaming only" is in here
  # because which recordings still cost double the disk is the whole reason
  # somebody is looking at this list.
  #
  # The authors lead it, bare, the way every other credit stack in the app
  # reads (§8) — this line listed a recording's narrators and never said who
  # wrote the thing, which is the one credit a picker of audiobooks can be
  # asked to disambiguate by.
  defp media_option_detail(%MediaFlat{} = media) do
    [
      names(media.authors),
      name_credit(media.narrators) && "read by #{name_credit(media.narrators)}",
      media.publisher,
      media.published && media.published.year,
      media.duration && format_duration(media.duration),
      !media.direct_play && "streaming only"
    ]
    |> Enum.filter(&(is_binary(&1) or is_integer(&1)))
    |> Enum.map_join(" · ", &to_string/1)
    |> presence()
  end

  defp names([]), do: nil
  defp names(nil), do: nil
  defp names(people), do: people |> Enum.map_join(", ", & &1.name) |> presence()

  # hh:mm, which is how long an audiobook is talked about.
  defp format_duration(seconds) do
    total = seconds |> Decimal.round() |> Decimal.to_integer()
    "#{div(total, 3600)}h #{total |> rem(3600) |> div(60)}m"
  end

  @doc """
  The recording these files were imported into, if any.

  Three kinds of recording answer this three ways, and the library holds
  all three at once: an **imported** one answers with the tracks it is
  served from; a **web-upload-era** one with the `source_files` its
  transcode consumed, which are copies the upload form made; a
  **server-import-era** one with `legacy_source_files`, the absolute
  downloads paths its transcode consumed, quarantined there because they
  point outside every root.

  The last two are transcode bookkeeping, which is exactly why they answer
  this question: what a recording was made from is what a file turning up
  again would be replacing.

  Compared as absolute disk paths on both sides, so which stored form a
  recording happens to use (root-relative, `/uploads/...`, or absolute) never
  has to be reasoned about at the comparison. The query that gathers
  candidates is deliberately loose — it may over-match across roots — and the
  overlap below is what decides.

  Returns `{:ok, media}` for the recording with the most files in common, or
  `:none`.
  """
  def imported_from(paths)
  def imported_from([]), do: :none

  def imported_from(paths) when is_list(paths) do
    wanted = MapSet.new(paths)

    paths
    |> candidate_media()
    |> Enum.map(fn media ->
      {media, Enum.count(recorded_files(media), &MapSet.member?(wanted, &1))}
    end)
    |> Enum.reject(fn {_media, shared} -> shared == 0 end)
    |> case do
      [] -> :none
      scored -> {:ok, scored |> Enum.max_by(fn {m, shared} -> {shared, -m.id} end) |> elem(0)}
    end
  end

  # Anything whose stored provenance *could* name one of these paths. Only
  # a file that falls inside a library root can be named by a relative
  # column, so a downloads folder — which is every ordinary source — costs
  # one query on the legacy column and nothing else.
  defp candidate_media(paths) do
    relatives = root_relative_forms(paths)

    legacy =
      Media
      |> where([m], fragment("? && ?::text[]", m.legacy_source_files, ^paths))
      |> Repo.all()

    placed =
      if relatives == [] do
        []
      else
        track_media_ids =
          MediaTrack |> where([t], t.path in ^relatives) |> select([t], t.media_id) |> Repo.all()

        Media
        |> where(
          [m],
          m.id in ^track_media_ids or
            (not is_nil(m.library_root_id) and
               fragment("? && ?::text[]", m.source_files, ^relatives))
        )
        |> Repo.all()
      end

    (legacy ++ placed) |> Enum.uniq_by(& &1.id) |> Repo.preload(:media_tracks)
  end

  # The stored form each path would have if a recording held it, for the
  # roots it might fall under. Roots are read once rather than per path.
  defp root_relative_forms(paths) do
    roots = Library.list_roots()

    for path <- paths,
        root <- roots,
        String.starts_with?(path, root.path <> "/"),
        do: Path.relative_to(path, root.path)
  end

  # Everywhere a recording says where its audio came from, as absolute paths.
  defp recorded_files(%Media{} = media) do
    Media.source_file_paths(media) ++
      (media.legacy_source_files || []) ++
      Enum.flat_map(media.media_tracks, &resolved_disk_path/1)
  end

  @doc """
  Returns the number of recordings, under the same filters `list_media/4`
  lists with — so a list can say what page it is of.

  ## Examples

      iex> count_media()
      1

  """
  @spec count_media(map()) :: integer()
  def count_media(filters \\ %{}) do
    filters |> MediaFlat.count_query() |> Repo.one()
  end

  @doc """
  The recordings that are in a state somebody has to do something about.

  Four counts, each of which names a different job:

    * `missing` — the nightly reconciliation couldn't read the files. Clients
      are being offered something that isn't there.
    * `errored` — a transcode gave up on it, and nothing will pick it back
      up: the way out is to import the files again.
    * `streaming_only` — no tracks, so the only way to play it is the legacy
      transcoding pipeline. It works, and it costs double the disk; clearing
      one means relinking it to its source (Phase 4). This is deliberately
      not phrased as progress toward a cutover — the cutover ends, and a
      widget that has to be retired the week after it lands was never
      describing the library, only the calendar.
    * `awaiting_switch` — direct-play recordings held back by the operator
      switch. The same predicate `publish_pending_direct_play/0` uses, so the
      number is exactly what turning it on would release.

  Zero is the answer that means "nothing to do", so every key is always
  present: an absent key and a zero read alike in a template, and only one of
  them is a measurement.
  """
  def problem_counts do
    tracked = from(t in MediaTrack, select: t.media_id, distinct: true)

    from(m in Media,
      select: %{
        missing: filter(count(m.id), not is_nil(m.missing_since)),
        errored: filter(count(m.id), m.status == :error),
        streaming_only: filter(count(m.id), m.id not in subquery(tracked)),
        awaiting_switch:
          filter(
            count(m.id),
            m.status == :pending and is_nil(m.missing_since) and is_nil(m.mp4_path) and
              is_nil(m.hls_path) and is_nil(m.mpd_path) and m.id in subquery(tracked)
          )
      }
    )
    |> Repo.one()
  end

  @doc """
  Gets a single media.

  Raises `Ecto.NoResultsError` if the Media does not exist.

  ## Examples

      iex> get_media!(123)
      %Media{}

      iex> get_media!(456)
      ** (Ecto.NoResultsError)

  """
  def get_media!(id),
    do:
      Media
      |> preload([:book, :media_narrators, :media_tracks, :recording_group])
      |> Repo.get!(id)

  @doc """
  Gets a media and the book with all its details.
  """
  def get_media_with_book_details!(id) do
    id
    |> media_with_book_details_query()
    |> Repo.get!(id)
  end

  @doc """
  Gets a media and the book with all its details.

  Returns `{:ok, media}` on success or `{:error, :not_found}`.
  """
  def fetch_media_with_book_details(id) do
    id
    |> media_with_book_details_query()
    |> Repo.fetch(id)
  end

  defp media_with_book_details_query(id) do
    media_query =
      from m in Media, where: m.status == :ready and m.id != ^id, order_by: {:desc, :published}

    group_media_query =
      from m in Media,
        where: m.status == :ready,
        order_by: [asc_nulls_last: m.part_number, asc: m.id]

    Media
    |> preload([
      :narrators,
      recording_group: [media: ^group_media_query],
      book: [
        :authors,
        series_books: :series,
        media:
          ^{media_query, [:narrators, :recording_group, book: [:authors, series_books: :series]]}
      ]
    ])
  end

  @doc """
  Fetches a single media.

  Returns `{:ok, media}` on success or `{:error, :not_found}`.

  ## Examples

      iex> fetch_media(123)
      {:ok, %Media{}}

      iex> fetch_media(456)
      {:error, :not_found}

  """
  # With its tracks: an imported recording keeps its files there, so a media
  # fetched without them is one you cannot ask what it is made of — and
  # `Ambry.Media.Scanner.audio_files/1` used to answer that question from the
  # empty transcode columns rather than refusing it.
  def fetch_media(id), do: Media |> preload(:media_tracks) |> Repo.fetch(id)

  @doc """
  Fetches a single direct-play track.

  Returns `{:ok, media_track}` on success or `{:error, :not_found}`.
  """
  def fetch_media_track(id), do: Repo.fetch(MediaTrack, id)

  @doc """
  Creates a media.

  ## Examples

      iex> create_media(%{field: value})
      {:ok, %Media{}}

      iex> create_media(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def create_media(attrs \\ %{}, opts \\ []) do
    opts = with_publishing_gate(opts)

    Repo.transact(fn ->
      changeset = Media.changeset(%Media{}, attrs, opts)

      with {:ok, media} <- Repo.insert(changeset),
           {:ok, _job_or_noop} <- generate_thumbnails_async(media),
           {:ok, _job} <- broadcast_media_created(media) do
        {:ok, media}
      end
    end)
  end

  # Whether a tracks-only recording may be published is an operator setting,
  # read here so the changeset stays a pure function of its inputs. Callers
  # may override it (the scanner never publishes either way).
  defp with_publishing_gate(opts) do
    Keyword.put_new_lazy(opts, :direct_play_publishing?, &Settings.direct_play_publishing?/0)
  end

  defp broadcast_media_created(%Media{} = media) do
    media
    |> MediaCreated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a media.

  ## Examples

      iex> update_media(media, %{field: new_value})
      {:ok, %Media{}}

      iex> update_media(media, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  Accepts `provenance: %{"field" => source}` in `opts` to record where
  provider-fillable field values came from — see `Ambry.Provenance`.
  """
  def update_media(%Media{} = media, attrs, opts \\ []) do
    opts = with_publishing_gate(opts)

    Repo.transact(fn ->
      changeset = Media.changeset(media, attrs, opts)

      with {:ok, updated_media} <- Repo.update(changeset),
           :ok <- delete_orphaned_recording_group(media.recording_group_id),
           {:ok, _job_or_noop} <- delete_unused_files_async(media, updated_media),
           {:ok, _job_or_noop} <- generate_thumbnails_async(updated_media),
           {:ok, _job} <- broadcast_media_updated(updated_media) do
        {:ok, updated_media}
      end
    end)
  end

  defp delete_unused_files_async(%Media{} = old_media, %Media{} = new_media) do
    (all_web_paths(old_media) -- all_web_paths(new_media))
    |> Enum.map(&Paths.web_to_disk/1)
    |> try_delete_files_async()
  end

  defp all_web_paths(%Media{} = media) do
    [media.image_path | if(media.thumbnails, do: all_web_paths(media.thumbnails), else: [])]
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  defp all_web_paths(%Thumbnails{} = thumbnails) do
    [
      thumbnails.extra_large,
      thumbnails.large,
      thumbnails.medium,
      thumbnails.small,
      thumbnails.extra_small
    ]
  end

  # A narrator row may *name* the person it credits instead of pointing at
  # them — see `Ambry.Ecto.EntityRef`. The name becomes a person here, inside
  # the transaction the recording is saved in, so a save that fails leaves
  # nobody behind.
  #
  defp broadcast_media_updated(%Media{} = media) do
    media
    |> MediaUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a media.

  ## Examples

      iex> delete_media(media)
      :ok

      iex> delete_media(media)
      {:error, %Ecto.Changeset{}}

  """
  def delete_media(%Media{} = media) do
    # Worked out *before* the delete: `media_tracks` cascades on
    # `on_delete: :delete_all`, so by the time the row is gone the record of
    # what this recording owned on disk is gone with it — and deletion would
    # silently fall through to whatever `source_path` happens to say.
    deletions = source_deletions(media)

    Repo.transact(fn ->
      with {:ok, deleted_media} <- Repo.delete(media),
           :ok <- delete_orphaned_recording_group(media.recording_group_id),
           {:ok, _job} <- delete_all_files_async(deleted_media, deletions),
           {:ok, _job} <- broadcast_media_deleted(deleted_media) do
        {:ok, deleted_media}
      end
    end)
  end

  defp broadcast_media_deleted(%Media{} = media) do
    media
    |> MediaDeleted.new()
    |> PubSub.broadcast_async()
  end

  defp delete_all_files_async(%Media{} = media, deletions) do
    delete_files_async(%{deletions | files: all_file_paths(media) ++ deletions.files})
  end

  @doc """
  The files a replacement retires: what this recording is served from now,
  plus the packaged artifacts it was streamed from.

  Read **before** the replacement writes anything, for the same reason
  `delete_media/1` reads it before the delete: `media_tracks` is the record
  of what a recording owns on disk, and once new tracks are written the old
  ones are gone. Same deletion semantics as `delete_media/1` — see
  `source_deletions/1` — because they are the same question.

  The cover and its thumbnails are deliberately absent. A replacement changes
  a recording's files, not the recording: its artwork, credits and chapters
  belong to the same audiobook and stay.
  """
  def retired_files(%Media{} = media) do
    deletions = source_deletions(media)
    %{deletions | files: artifact_paths(media) ++ deletions.files}
  end

  @doc """
  Deletes a worked-out set of files in the background, pruning what it empties.
  """
  def delete_files_async(%{folders: folders, files: files, prune_from: prune_from}) do
    try_delete_files_async(files, folders,
      prune_until: if(folders != [] or prune_from != [], do: library_root_paths()),
      prune_from: prune_from
    )
  end

  @doc """
  Whether this recording's files are the only name their bytes have.

  What the replace decision's warning asks. A hardlinked library copy shares
  its inode with the source it was placed from, so the bytes have another
  name and removing this one destroys nothing — there is nothing to warn
  about. The link count is what says that *now*, which is the honest test: a
  recording hardlinked from a torrent that has since been removed has a link
  count of 1, and its files really are the last copy.

  True for a recording with nothing to ask about, and true for any file that
  can't be stat'd. A warning that hides when it shouldn't is worse than one
  that always shows.
  """
  def only_copy?(media_id) when is_integer(media_id) do
    case Repo.get(Media, media_id) do
      nil -> false
      media -> only_copy?(media)
    end
  end

  def only_copy?(%Media{} = media) do
    case served_files(media) do
      [] -> true
      files -> not Enum.all?(files, &hardlinked?/1)
    end
  end

  defp hardlinked?(path) do
    match?({:ok, %File.Stat{links: links}} when links > 1, File.stat(path))
  end

  # What the recording plays from right now: its tracks where it has them,
  # its recorded source files where it doesn't.
  defp served_files(%Media{} = media) do
    case owned_tracks(media) do
      [] -> Media.source_file_paths(media)
      tracks -> Enum.flat_map(tracks, &resolved_disk_path/1)
    end
  end

  # The registered locations are where pruning stops: a root's existence is
  # configuration, not a consequence of currently holding a book.
  defp library_root_paths do
    Library.registered_paths()
  end

  # Deletion semantics (roadmap 3a, custody collapsed by the paths refactor).
  #
  # Every recording's files are Ambry's own name for the bytes — a file
  # placed into a library root, or the legacy transcoded workspace — and
  # removing the recording removes that name. The original a placement was
  # made from is untouched by construction: a hardlink is a separate name
  # for the same inode, a symlink is unlinked without being followed, a
  # copy never knew its original, and a move's original is already gone.
  #
  # Transcoded outputs, images and thumbnails are always Ambry's own, under
  # the uploads path, so they're removed too.
  #
  # ## A recording with tracks deletes files, never folders
  #
  # `media_tracks` names every file the recording is served from, so those
  # are exactly what deletion removes — one `File.rm/1` each, and nothing
  # else. No folder is handed to `rm_rf` at all.
  #
  # The point is not that a folder might hold something foreign — a root is
  # Ambry's, and nothing else writes there. It is that a folder deletion has
  # to be *right*, and a file deletion cannot be wrong. A book folder really
  # is shared: every recording of that book sits in it, and a single-file
  # recording sits in it directly. Removing only the files you own makes "is
  # this folder shared", "does another part of the set live here" and "is
  # this somehow the library root itself" stop being questions. An earlier
  # draft of this answered all three, and getting them right was harder than
  # not asking.
  #
  # What it leaves behind is empty folders, which is a tidiness problem
  # rather than a correctness one, and pruning already solves it: after the
  # files go, walk up from where they were removing folders that are now
  # empty, stopping at a registered root.
  #
  # `source_path` is the fallback, and only for a recording with no tracks.
  # There it still means what it first meant — the upload workspace Ambry
  # created, which holds more than the audio (progress files, the `_out`
  # folder) and genuinely is Ambry's to remove wholesale. That clause, and
  # the last `rm_rf` with it, retires when the reclaim leaves nothing
  # without tracks.
  defp source_deletions(%Media{} = media) do
    case owned_tracks(media) do
      [] -> legacy_source_deletions(media)
      tracks -> track_deletions(tracks)
    end
  end

  # Asked of the database rather than a preload, and *before* the row is
  # deleted: `media_tracks` cascades on `on_delete: :delete_all`, so asking
  # afterwards returns an empty list and falls silently through to the legacy
  # clause. An unloaded assoc reads the same way. One cheap query is the
  # right price for an operation that removes files.
  defp owned_tracks(%Media{id: id}) do
    Repo.all(from t in MediaTrack, where: t.media_id == ^id)
  end

  defp track_deletions(tracks) do
    files = Enum.flat_map(tracks, &resolved_disk_path/1)
    %{folders: [], files: files, prune_from: files}
  end

  defp resolved_disk_path(track) do
    case MediaTrack.disk_path(track) do
      {:ok, path} -> [path]
      {:error, _reason} -> []
    end
  end

  # A folder shared with a sibling is not this media's to remove: a
  # multi-part recording places every part in one book folder, so deleting
  # part 1 with an rm_rf of the folder would take part 2's file with it.
  # A shared folder yields only the media's own files; the folder itself
  # goes with its last part.
  defp legacy_source_deletions(%Media{source_path: path} = media) when is_binary(path) do
    if shared_source_path?(media),
      do: %{folders: [], files: Media.source_file_paths(media), prune_from: []},
      else: %{folders: [Media.source_path(media)], files: [], prune_from: []}
  end

  defp legacy_source_deletions(%Media{}), do: %{folders: [], files: [], prune_from: []}

  # Compared as {root, relative} rather than as strings: two roots may
  # legitimately hold the same relative path, and they are different folders.
  defp shared_source_path?(%Media{id: id, source_path: path, library_root_id: root_id}) do
    Media
    |> where([m], m.source_path == ^path and m.id != ^id)
    |> same_root(root_id)
    |> Repo.exists?()
  end

  defp same_root(query, nil), do: where(query, [m], is_nil(m.library_root_id))
  defp same_root(query, root_id), do: where(query, [m], m.library_root_id == ^root_id)

  defp all_file_paths(%Media{} = media) do
    media_files = artifact_web_paths(media)

    image_files = [media.image_path]

    thumbnail_files =
      case media.thumbnails do
        nil ->
          []

        thumbnails ->
          [
            thumbnails.extra_large,
            thumbnails.large,
            thumbnails.medium,
            thumbnails.small,
            thumbnails.extra_small
          ]
      end

    (media_files ++ image_files ++ thumbnail_files)
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.map(&Paths.web_to_disk/1)
  end

  # The packaged outputs a legacy recording streams and downloads from,
  # always Ambry's own under the uploads path. Named apart from the artwork
  # because a replacement retires these and keeps that.
  defp artifact_paths(%Media{} = media) do
    media
    |> artifact_web_paths()
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.map(&Paths.web_to_disk/1)
  end

  defp artifact_web_paths(%Media{} = media) do
    [media.mpd_path, media.hls_path, media.mp4_path, Paths.hls_playlist_path(media.hls_path)]
  end

  @doc """
  Schedules an Oban job to generate thumbnails for a media asynchronously.
  Only schedules the job if the media has an image path but no thumbnails.

  ## Examples

      iex> generate_thumbnails_async(media)
      {:ok, %Oban.Job{}}

      iex> generate_thumbnails_async(media_with_thumbnails)
      {:ok, :noop}
  """
  def generate_thumbnails_async(%Media{image_path: image_path, thumbnails: nil} = media)
      when is_binary(image_path) do
    %{"media_id" => media.id, "image_path" => image_path}
    |> GenerateThumbnails.new()
    |> Oban.insert()
  end

  def generate_thumbnails_async(_media), do: {:ok, :noop}

  @doc """
  The short identifier a recording's files carry in the library.

  See `Ambry.Media.Media.filename_token/1`.
  """
  defdelegate filename_token(media), to: Media

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking media changes.

  ## Examples

      iex> change_media(media)
      %Ecto.Changeset{data: %Media{}}

  """
  def change_media(%Media{} = media, attrs \\ %{}) do
    Media.changeset(media, attrs)
  end

  @doc """
  Returns a limited list of recording groups and whether or not there are
  more, for the admin index. Each group carries a `:media` preload (with
  books) ordered by part number.

  Supports the `%{search: name}` filter and ordering by `:name` or
  `:inserted_at`.
  """
  def list_recording_groups(offset \\ 0, limit \\ 10, filters \\ %{}, order \\ [asc: :name]) do
    over_limit = limit + 1

    groups =
      RecordingGroup
      |> recording_group_filter(filters)
      |> recording_group_order(order)
      |> offset(^offset)
      |> limit(^over_limit)
      |> preload([:book, :media])
      |> Repo.all()

    groups_to_return = Enum.slice(groups, 0, limit)

    {groups_to_return, groups != groups_to_return}
  end

  defp recording_group_filter(query, %{search: search}) when is_binary(search) and search != "" do
    where(query, [g], ilike(g.name, ^"%#{search}%"))
  end

  defp recording_group_filter(query, _filters), do: query

  # accepts the pagination helpers' `{field, dir}` shape as well as plain
  # keyword orders, like the flat schemas' order/2 does — including their
  # `id` tiebreaker, without which two groups sharing a name have no defined
  # order between two queries and can swap across a page boundary
  defp recording_group_order(query, {field, dir}),
    do: order_by(query, ^[{dir, field}, {:asc, :id}])

  defp recording_group_order(query, nil), do: order_by(query, asc: :name, asc: :id)
  defp recording_group_order(query, order), do: order_by(query, ^(order ++ [asc: :id]))

  @doc """
  Returns the number of recording groups, under the same filters
  `list_recording_groups/4` lists with.
  """
  @spec count_recording_groups(map()) :: integer()
  def count_recording_groups(filters \\ %{}) do
    RecordingGroup |> recording_group_filter(filters) |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single recording group with its media (and their books) preloaded
  in part order.

  Raises `Ecto.NoResultsError` if the group does not exist.
  """
  def get_recording_group!(id) do
    RecordingGroup
    |> preload([:book, media: :book])
    |> Repo.get!(id)
  end

  @doc """
  Creates a recording group.

  A group with no members is allowed — groups are first-class entities an
  operator may set up ahead of its parts. (Groups that *lose* their last
  member through a media save are still swept as orphans.)
  """
  def create_recording_group(attrs) do
    Repo.transact(fn ->
      changeset = RecordingGroup.changeset(%RecordingGroup{}, attrs)

      with {:ok, group} <- Repo.insert(changeset),
           {:ok, _job} <- broadcast_recording_group_created(group) do
        {:ok, group}
      end
    end)
  end

  defp broadcast_recording_group_created(%RecordingGroup{} = group) do
    group
    |> RecordingGroupCreated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a recording group.
  """
  def update_recording_group(%RecordingGroup{} = group, attrs) do
    Repo.transact(fn ->
      changeset = RecordingGroup.changeset(group, attrs)

      with {:ok, updated_group} <- Repo.update(changeset),
           {:ok, _job} <- broadcast_recording_group_updated(updated_group) do
        {:ok, updated_group}
      end
    end)
  end

  defp broadcast_recording_group_updated(%RecordingGroup{} = group) do
    group
    |> RecordingGroupUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a recording group, detaching its members.

  The FK nils members' `recording_group_id`; their `part_number` must go
  with it (a part number without a group violates the data model — and the
  DB CHECK the FK's nilify would otherwise trip).
  """
  def delete_recording_group(%RecordingGroup{} = group) do
    Repo.transact(fn ->
      Repo.update_all(
        from(m in Media, where: m.recording_group_id == ^group.id),
        set: [part_number: nil, recording_group_id: nil, updated_at: DateTime.utc_now(:second)]
      )

      with {:ok, deleted_group} <- Repo.delete(change_recording_group(group)),
           {:ok, _job} <- broadcast_recording_group_deleted(deleted_group.id) do
        {:ok, deleted_group}
      end
    end)
  end

  defp broadcast_recording_group_deleted(id) do
    id
    |> RecordingGroupDeleted.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recording group changes.
  """
  def change_recording_group(%RecordingGroup{} = group, attrs \\ %{}) do
    RecordingGroup.changeset(group, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for the group admin form — the group's own
  facts plus its members, shaped for `inputs_for` like a series' books.
  """
  def change_recording_group_form(%RecordingGroup{} = group, attrs \\ %{}) do
    group |> RecordingGroupForm.from_group() |> RecordingGroupForm.changeset(attrs)
  end

  @doc """
  Creates a group from the admin form, attaching any listed members.
  """
  def create_recording_group_from_form(attrs) do
    save_recording_group_form(%RecordingGroup{media: []}, attrs, fn params ->
      create_recording_group(params)
    end)
  end

  @doc """
  Updates a group from the admin form, diffing its member list.

  A removed row detaches the media (clearing its part number — a position in
  a set it left isn't a fact to keep); rows write membership through
  `update_media/3` so search, sync, PubSub and the orphan sweep all fire.
  """
  def update_recording_group_from_form(%RecordingGroup{} = group, attrs) do
    save_recording_group_form(group, attrs, fn params ->
      update_recording_group(group, params)
    end)
  end

  defp save_recording_group_form(group, attrs, save_group) do
    changeset = change_recording_group_form(group, attrs)

    with {:ok, form} <- Ecto.Changeset.apply_action(changeset, :save) do
      Repo.transact(fn ->
        with {:ok, saved} <- save_group.(group_params(form)),
             :ok <- apply_group_members(saved, group.media || [], form.members) do
          {:ok, saved}
        end
      end)
    end
  end

  defp group_params(form) do
    %{
      name: form.name,
      book_id: form.book_id,
      parts_total: form.parts_total,
      show_label: form.show_label,
      part_word: form.part_word,
      part_word_plural: form.part_word_plural
    }
  end

  defp apply_group_members(group, current_members, members) do
    desired = Map.new(members, &{&1.media_id, &1.part_number})

    detached =
      for %Media{} = media <- current_members, not Map.has_key?(desired, media.id) do
        {media.id, %{recording_group_id: nil, part_number: nil}}
      end

    attached =
      for {media_id, part_number} <- desired do
        {media_id, %{recording_group_id: group.id, part_number: part_number}}
      end

    Enum.reduce_while(detached ++ attached, :ok, fn {media_id, attrs}, :ok ->
      case update_media(get_media!(media_id), attrs) do
        {:ok, _media} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp presence(""), do: nil
  defp presence(other), do: other

  @doc """
  Subscribes to all recording group CRUD messages.
  """
  def subscribe_to_recording_group_crud_messages do
    :ok = PubSub.subscribe(RecordingGroupCreated.wildcard_topic())
    :ok = PubSub.subscribe(RecordingGroupUpdated.wildcard_topic())
    :ok = PubSub.subscribe(RecordingGroupDeleted.wildcard_topic())
  end

  @doc """
  One recording group as a picker option, or nil.
  """
  def recording_group_option(blank) when blank in [nil, ""], do: nil

  def recording_group_option(%RecordingGroup{} = group) do
    %{
      id: group.id,
      label: group.name,
      image: first_member_thumbnail(group),
      detail: parts_progress(group),
      # A member's form states the set's total rather than asking for it, so
      # the option has to carry the number and not only the words.
      parts_total: group.parts_total
    }
  end

  def recording_group_option(id) do
    RecordingGroup |> preload(:media) |> Repo.get(id) |> recording_group_option()
  end

  defp first_member_thumbnail(%RecordingGroup{media: media}) do
    Enum.find_value(media, &(&1.thumbnails && &1.thumbnails.extra_small))
  end

  defp parts_progress(%RecordingGroup{media: media} = group) do
    count = length(media)
    word = RecordingGroup.part_word_plural(group)

    case group.parts_total do
      nil -> "#{count} #{word}"
      total -> "#{count} of #{total} #{word}"
    end
  end

  @doc """
  Every set of one book, as picker options.

  A book has one set, or none, or occasionally two. That is a drop-down.
  """
  def recording_group_options(book_id) do
    book_id
    |> recording_groups_for_book()
    |> Repo.preload(:media)
    |> Enum.map(&recording_group_option/1)
  end

  @doc """
  Returns the full recording groups belonging to the given book, in id
  order. This is what the inbox consults to propose "another part of the
  same set?" when a later part of an already-imported work arrives.
  """
  def recording_groups_for_book(nil), do: []

  def recording_groups_for_book(book_id) do
    Repo.all(from g in RecordingGroup, where: g.book_id == ^book_id, order_by: g.id)
  end

  # A group whose last member just left it is swept (the delete trigger
  # records it for sync; subscribers hear about it too). Scoped to the group
  # the saved media *came from* — never a global sweep, so an admin-created
  # empty group survives unrelated media saves while it awaits its parts.
  defp delete_orphaned_recording_group(nil), do: :ok

  defp delete_orphaned_recording_group(group_id) do
    {deleted, _} =
      Repo.delete_all(
        from g in RecordingGroup,
          where: g.id == ^group_id,
          where: not exists(from m in Media, where: m.recording_group_id == ^group_id)
      )

    if deleted > 0 do
      {:ok, _job} = broadcast_recording_group_deleted(group_id)
    end

    :ok
  end

  @doc """
  Returns a paginated list of media narrated by the given narrator.
  """
  def get_narrated_media(narrator, offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    # users never see non-ready audiobooks (tile system v2, rule 1)
    query =
      from b in Ecto.assoc(narrator, :media),
        where: b.status == :ready,
        order_by: [desc: b.published],
        offset: ^offset,
        limit: ^over_limit,
        preload: [book: [:authors, series_books: :series]]

    media = Repo.all(query)

    media_to_return = Enum.slice(media, 0, limit)

    {media_to_return, media != media_to_return}
  end

  @doc """
  Lists recent media.
  """
  def get_recent_media(offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    # part sets collapse to one entry: only the first ready part of each
    # recording group represents its set
    query =
      from m in Media,
        where: m.status == :ready,
        where:
          is_nil(m.recording_group_id) or
            m.id ==
              fragment(
                """
                (SELECT m2.id FROM media m2
                 WHERE m2.recording_group_id = ? AND m2.status = 'ready'
                 ORDER BY m2.part_number ASC NULLS LAST, m2.id ASC
                 LIMIT 1)
                """,
                m.recording_group_id
              ),
        order_by: [desc: m.inserted_at],
        offset: ^offset,
        limit: ^over_limit

    group_media_query =
      from m in Media,
        where: m.status == :ready,
        order_by: [asc_nulls_last: m.part_number, asc: m.id]

    media =
      query
      |> preload(
        book: [:authors, series_books: :series],
        recording_group: [media: ^group_media_query]
      )
      |> Repo.all()

    media_to_return = Enum.slice(media, 0, limit)

    {media_to_return, media != media_to_return}
  end

  @doc """
  Updates thumbnails for the given media ID and image path.

  This is used by the Oban job to generate thumbnails for media.
  """
  def update_media_thumbnails!(media_id, image_web_path) do
    thumbnails = Ambry.Thumbnails.generate_thumbnails!(image_web_path)
    media = get_media!(media_id)

    case update_media(media, %{thumbnails: thumbnails}) do
      {:ok, updated_media} ->
        {:ok, updated_media}

      {:error, changeset} ->
        # Delete the new thumbnails from disk, because the update failed.
        Thumbnails.try_delete_thumbnails(thumbnails)

        {:error, changeset}
    end
  end

  @doc """
  Returns a description of a media containing the book's title, narrator names, and author names.
  """
  def get_media_description(%Media{} = media) do
    %{book: book, narrators: narrators} = Repo.preload(media, [:book, :narrators])
    narrators = Enum.map_join(narrators, ", ", & &1.name)

    description = Books.get_book_description(book)

    # recordings are described by their display title (override or part label)
    description =
      String.replace_prefix(
        description,
        book.title,
        Media.display_title(%{media | book: book})
      )

    "#{description} read by #{narrators}"
  end

  @doc """
  Subscribes to all media CRUD messages.
  """
  def subscribe_to_media_crud_messages do
    :ok = PubSub.subscribe(MediaCreated.wildcard_topic())
    :ok = PubSub.subscribe(MediaUpdated.wildcard_topic())
    :ok = PubSub.subscribe(MediaDeleted.wildcard_topic())
  end
end
