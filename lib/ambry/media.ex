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
      PubSub.MediaProgress,
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
  alias Ambry.Media.Processor
  alias Ambry.Media.PubSub.MediaCreated
  alias Ambry.Media.PubSub.MediaDeleted
  alias Ambry.Media.PubSub.MediaProgress
  alias Ambry.Media.PubSub.MediaUpdated
  alias Ambry.Media.PubSub.RecordingGroupCreated
  alias Ambry.Media.PubSub.RecordingGroupDeleted
  alias Ambry.Media.PubSub.RecordingGroupUpdated
  alias Ambry.Media.RecordingGroup
  alias Ambry.Media.RecordingGroupForm
  alias Ambry.Media.RunOrganize
  alias Ambry.Media.RunProcessor
  alias Ambry.Media.RunPublishPending
  alias Ambry.Media.RunScan
  alias Ambry.Media.Scanner
  alias Ambry.Paths
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search
  alias Ambry.Settings
  alias Ambry.Thumbnails
  alias Ambry.Thumbnails.GenerateThumbnails

  defdelegate get_media_file_details(media), to: Audit
  defdelegate orphaned_files_audit(), to: Audit

  @doc """
  Brings a recording's managed files back in line with the naming template.

  Asynchronous because it touches the filesystem, and safe to call after any
  edit: a recording that is already where it belongs, external, or outside a
  library root is a no-op.
  """
  def organize_async(%Media{id: id}), do: enqueue_organize(%{"media_id" => id})

  @doc """
  The same, for every managed recording of a book.

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
  That last pair matters: a legacy recording sitting in `pending` is waiting
  on transcoding, not on this switch, and publishing a recording whose files
  have vanished would hand clients something unplayable.
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
  Returns the number of uploaded media.

  ## Examples

      iex> count_media()
      1

  """
  @spec count_media :: integer()
  def count_media do
    Repo.aggregate(Media, :count)
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
  def fetch_media(id), do: Repo.fetch(Media, id)

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
           :ok <- Search.insert(media),
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
           :ok <- Search.update(updated_media),
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
    Repo.transact(fn ->
      with {:ok, deleted_media} <- Repo.delete(media),
           :ok <- delete_orphaned_recording_group(media.recording_group_id),
           :ok <- Search.delete(deleted_media),
           {:ok, _job} <- delete_all_files_async(deleted_media),
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

  defp delete_all_files_async(%Media{} = media) do
    {folders, own_files} = source_deletions(media)

    try_delete_files_async(all_file_paths(media) ++ own_files, folders,
      prune_until: if(folders != [], do: library_root_paths())
    )
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
  # This is still worth care: the deletion worker runs `File.rm_rf` on
  # every folder it's given, so `source_path` must always be a folder that
  # is Ambry's to remove.
  #
  # Transcoded outputs, images and thumbnails are always Ambry's own, under
  # the uploads path, so they're removed too.
  # A folder shared with a sibling is not this media's to remove: a
  # multi-part recording places every part in one book folder, so deleting
  # part 1 with an rm_rf of `source_path` would take part 2's file with it.
  # A shared folder yields only the media's own files; the folder itself
  # goes with its last part.
  defp source_deletions(%Media{source_path: path} = media) when is_binary(path) do
    if shared_source_path?(media),
      do: {[], Media.source_file_paths(media)},
      else: {[Media.source_path(media)], []}
  end

  defp source_deletions(%Media{}), do: {[], []}

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
    %Media{
      mpd_path: mpd_path,
      hls_path: hls_path,
      mp4_path: mp4_path
    } = media

    media_files = [
      mpd_path,
      hls_path,
      mp4_path,
      Paths.hls_playlist_path(hls_path)
    ]

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
  Runs a processor asynchronously for the given media.
  """
  def run_processor_async(%Media{} = media, processor) do
    %{media_id: media.id, processor: processor}
    |> RunProcessor.new()
    |> Oban.insert()
  end

  @doc """
  Scans a media's source files into direct-play tracks.

  Delegates to `Ambry.Media.Scanner`; returns `{:ok, media}` or
  `{:error, reason}`.
  """
  defdelegate scan_media(media), to: Scanner, as: :scan

  @doc """
  The short identifier a recording's files carry in the library.

  See `Ambry.Media.Media.filename_token/1`.
  """
  defdelegate filename_token(media), to: Media

  @doc """
  Scans a media's source files asynchronously.
  """
  def scan_media_async(%Media{} = media) do
    %{media_id: media.id}
    |> RunScan.new()
    |> Oban.insert()
  end

  @doc """
  Replaces a media's source audio files with a new set of files and re-runs
  processing, overwriting the streaming output files in place.

  This is intended for swapping in corrected files for the *same*
  edition/recording (for example, fixing a corrupt, mistagged, or low-quality
  source) — not for switching to a different edition. Because the timeline is
  expected to line up, chapters and listeners' saved positions are deliberately
  left untouched.

  The streaming output files keep the same URLs (they are overwritten in place);
  `Plug.Static` serves them with mtime-based ETags, so clients revalidate and
  pick up the new audio the next time they play. Offline downloads in the mobile
  app are *not* automatically invalidated and must be re-downloaded by the user.

  The previous source folder is deleted asynchronously once the new files are in
  place.

  ## Examples

      iex> replace_media(media, %{source_path: path, source_files: files, processor: :auto})
      {:ok, %Media{}}

  """
  def replace_media(%Media{} = media, %{
        source_path: source_path,
        source_files: source_files,
        processor: processor
      }) do
    old_stored = media.source_path
    old_disk = old_stored && Media.source_path(media)

    with {:ok, updated_media} <-
           update_media(media, %{
             source_path: source_path,
             source_files: source_files,
             status: :pending
           }),
         {:ok, _job} <- run_processor_async(updated_media, processor) do
      delete_old_source_folder_async(old_stored, old_disk, source_path)
      {:ok, updated_media}
    end
  end

  # Same rule as deletion: the old folder is Ambry's name for the bytes and
  # goes with the replacement; any original it was placed from is untouched
  # by construction. Compared in stored form, deleted in resolved form.
  defp delete_old_source_folder_async(old_stored, _old_disk, new_source_path)
       when old_stored in [nil, new_source_path], do: {:ok, :noop}

  defp delete_old_source_folder_async(_old_stored, old_disk, _new_source_path),
    do: try_delete_files_async([], [old_disk])

  defdelegate available_processors(media_or_filenames), to: Processor, as: :matched_processors

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
  # keyword orders, like the flat schemas' order/2 does
  defp recording_group_order(query, {field, dir}), do: order_by(query, [{^dir, ^field}])
  defp recording_group_order(query, nil), do: order_by(query, asc: :name)
  defp recording_group_order(query, order), do: order_by(query, ^order)

  @doc """
  Returns the number of recording groups.
  """
  @spec count_recording_groups :: integer()
  def count_recording_groups do
    Repo.aggregate(RecordingGroup, :count)
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

  @doc """
  Returns one book's recordings for `Select` components, as rich options:
  cover, display title, and what actually tells two recordings of one book
  apart — publisher, year, and the narrator when the cast is small (a
  full-cast roster reads as noise, so it collapses to a count).
  """
  def media_for_select(nil), do: []
  def media_for_select(""), do: []

  def media_for_select(book_id) do
    query =
      from m in Media,
        where: m.book_id == ^book_id,
        order_by: m.id,
        preload: [:book, :recording_group, media_narrators: :narrator]

    query
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.title || &1.book.title,
        image: &1.thumbnails && &1.thumbnails.extra_small,
        detail: media_select_detail(&1)
      }
    )
  end

  defp media_select_detail(%Media{} = media) do
    narrators = Enum.map(media.media_narrators, & &1.narrator.name)

    [
      media.publisher,
      media.published && media.published.year,
      case narrators do
        [] -> nil
        [one] -> one
        [one, two] -> "#{one}, #{two}"
        [first | rest] -> "#{first} +#{length(rest)}"
      end,
      # picking a grouped recording MOVES it — the one membership fact
      # that's a warning rather than decoration
      media.recording_group && "in “#{media.recording_group.name}”"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" · ", &to_string/1)
    |> presence()
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
  Returns the given book's recording groups for `Select` components, as
  rich options: the set's name, its first part's cover, and how far along
  it is ("2 of 3 parts", in the group's own wording). Book-scoped — a
  group belongs to a book the way its members do, and a freshly created
  empty group is offerable because the FK carries the book even before
  any member does.
  """
  def recording_groups_for_select(nil), do: []
  def recording_groups_for_select(""), do: []

  def recording_groups_for_select(book_id) do
    query =
      from g in RecordingGroup,
        where: g.book_id == ^book_id,
        order_by: g.id,
        preload: :media

    query
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.id,
        label: &1.name,
        image: first_member_thumbnail(&1),
        detail: parts_progress(&1)
      }
    )
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

  @doc """
  Subscribes media processing progress messages.
  """
  def subscribe_to_media_progress_messages do
    :ok = PubSub.subscribe(MediaProgress.wildcard_topic())
  end
end
