defmodule Ambry.Media do
  @moduledoc """
  Functions for dealing with Media.
  """

  use Boundary,
    deps: [Ambry],
    exports: [
      Audit,
      Bookmark,
      Chapters,
      Media,
      Media.Chapter,
      MediaFlat,
      MediaNarrator,
      RecordingGroup,
      PubSub.MediaCreated,
      PubSub.MediaDeleted,
      PubSub.MediaProgress,
      PubSub.MediaUpdated
    ]

  import Ambry.Utils
  import Ecto.Query

  alias Ambry.Books
  alias Ambry.Media.Audit
  alias Ambry.Media.Bookmark
  alias Ambry.Media.Media
  alias Ambry.Media.MediaFlat
  alias Ambry.Media.Processor
  alias Ambry.Media.PubSub.BookmarkCreated
  alias Ambry.Media.PubSub.BookmarkDeleted
  alias Ambry.Media.PubSub.BookmarkUpdated
  alias Ambry.Media.PubSub.MediaCreated
  alias Ambry.Media.PubSub.MediaDeleted
  alias Ambry.Media.PubSub.MediaProgress
  alias Ambry.Media.PubSub.MediaUpdated
  alias Ambry.Media.RecordingGroup
  alias Ambry.Media.RunProcessor
  alias Ambry.Paths
  alias Ambry.PubSub
  alias Ambry.Repo
  alias Ambry.Search
  alias Ambry.Thumbnails
  alias Ambry.Thumbnails.GenerateThumbnails

  defdelegate get_media_file_details(media), to: Audit
  defdelegate orphaned_files_audit(), to: Audit

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
    do: Media |> preload([:book, :media_narrators, :recording_group]) |> Repo.get!(id)

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
        media: ^{media_query, [:narrators, book: [:authors, series_books: :series]]}
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
  Creates a media.

  ## Examples

      iex> create_media(%{field: value})
      {:ok, %Media{}}

      iex> create_media(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_media(attrs \\ %{}) do
    Repo.transact(fn ->
      changeset = Media.changeset(%Media{}, attrs)

      with {:ok, media} <- Repo.insert(changeset),
           :ok <- Search.insert(media),
           {:ok, _job_or_noop} <- generate_thumbnails_async(media),
           {:ok, _job} <- broadcast_media_created(media) do
        {:ok, media}
      end
    end)
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

  """
  def update_media(%Media{} = media, attrs) do
    Repo.transact(fn ->
      changeset = Media.changeset(media, attrs)

      with {:ok, updated_media} <- Repo.update(changeset),
           :ok <- delete_orphaned_recording_groups(),
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
           :ok <- delete_orphaned_recording_groups(),
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
    files_to_delete = all_file_paths(media)
    folders_to_delete = [media.source_path]

    try_delete_files_async(files_to_delete, folders_to_delete)
  end

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
  Replaces a media's source audio files with a new set of files and re-runs
  processing, overwriting the streaming output files in place.

  This is intended for swapping in corrected files for the *same*
  edition/recording (for example, fixing a corrupt, mistagged, or low-quality
  source) — not for switching to a different edition. Because the timeline is
  expected to line up, chapters and listeners' saved positions and bookmarks are
  deliberately left untouched.

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
    old_source_path = media.source_path

    with {:ok, updated_media} <-
           update_media(media, %{
             source_path: source_path,
             source_files: source_files,
             status: :pending
           }),
         {:ok, _job} <- run_processor_async(updated_media, processor) do
      delete_old_source_folder_async(old_source_path, source_path)
      {:ok, updated_media}
    end
  end

  defp delete_old_source_folder_async(old_source_path, new_source_path)
       when old_source_path in [nil, new_source_path], do: {:ok, :noop}

  defp delete_old_source_folder_async(old_source_path, _new_source_path),
    do: try_delete_files_async([], [old_source_path])

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
  Returns the recording groups usable for the given book, for `Select`
  components: every group already attached to one of the book's media.
  """
  def recording_groups_for_select(nil), do: []
  def recording_groups_for_select(""), do: []

  def recording_groups_for_select(book_id) do
    query =
      from g in RecordingGroup,
        join: m in assoc(g, :media),
        on: m.book_id == ^book_id,
        distinct: true,
        order_by: g.id,
        select: {g.name, g.id}

    query
    |> Repo.all()
    |> Enum.map(fn
      {nil, id} -> {"Unnamed group ##{id}", id}
      {name, id} -> {name, id}
    end)
  end

  # Groups exist only to tie parts together; once no media references one it
  # is deleted (the delete trigger records it for sync).
  defp delete_orphaned_recording_groups do
    Repo.delete_all(
      from g in RecordingGroup,
        as: :group,
        where: not exists(from m in Media, where: m.recording_group_id == parent_as(:group).id)
    )

    :ok
  end

  @doc """
  Returns a paginated list of media narrated by the given narrator.
  """
  def get_narrated_media(narrator, offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    query =
      from b in Ecto.assoc(narrator, :media),
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

    "#{description} • narrated by #{narrators}"
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

  @doc """
  Gets all bookmarks for a media for a user.
  """
  def list_bookmarks(user_id, media_id) do
    Bookmark
    |> where([b], b.media_id == ^media_id and b.user_id == ^user_id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  Lists bookmarks paginated.
  """
  def list_bookmarks(user_id, media_id, offset, limit) do
    over_limit = limit + 1

    query =
      from b in Bookmark,
        where: b.media_id == ^media_id and b.user_id == ^user_id,
        order_by: b.position,
        offset: ^offset,
        limit: ^over_limit

    bookmarks = Repo.all(query)

    bookmarks_to_return = Enum.slice(bookmarks, 0, limit)

    {bookmarks_to_return, bookmarks != bookmarks_to_return}
  end

  @doc """
  Gets a single bookmark.

  Raises `Ecto.NoResultsError` if the Bookmark does not exist.

  ## Examples

      iex> get_bookmark!(123)
      %Bookmark{}

      iex> get_bookmark!(456)
      ** (Ecto.NoResultsError)

  """
  def get_bookmark!(id), do: Repo.get!(Bookmark, id)

  @doc """
  Creates a bookmark.

  ## Examples

      iex> create_bookmark(%{field: value})
      {:ok, %Bookmark{}}

      iex> create_bookmark(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_bookmark(attrs) do
    Repo.transact(fn ->
      changeset = Bookmark.changeset(%Bookmark{}, attrs)

      with {:ok, bookmark} <- Repo.insert(changeset),
           {:ok, _job} <- broadcast_bookmark_created(bookmark) do
        {:ok, bookmark}
      end
    end)
  end

  defp broadcast_bookmark_created(%Bookmark{} = bookmark) do
    bookmark
    |> BookmarkCreated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a bookmark.

  ## Examples

      iex> update_bookmark(bookmark, %{field: new_value})
      {:ok, %Bookmark{}}

      iex> update_bookmark(bookmark, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_bookmark(%Bookmark{} = bookmark, attrs) do
    Repo.transact(fn ->
      changeset = Bookmark.changeset(bookmark, attrs)

      with {:ok, updated_bookmark} <- Repo.update(changeset),
           {:ok, _job} <- broadcast_bookmark_updated(updated_bookmark) do
        {:ok, updated_bookmark}
      end
    end)
  end

  defp broadcast_bookmark_updated(%Bookmark{} = bookmark) do
    bookmark
    |> BookmarkUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Deletes a bookmark.

  ## Examples

      iex> delete_bookmark(bookmark)
      {:ok, bookmark}

      iex> delete_bookmark(bookmark)
      {:error, %Ecto.Changeset{}}

  """
  def delete_bookmark(%Bookmark{} = bookmark) do
    Repo.transact(fn ->
      with {:ok, deleted_bookmark} <- Repo.delete(bookmark),
           {:ok, _job} <- broadcast_bookmark_deleted(deleted_bookmark) do
        {:ok, deleted_bookmark}
      end
    end)
  end

  defp broadcast_bookmark_deleted(%Bookmark{} = bookmark) do
    bookmark
    |> BookmarkDeleted.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bookmark changes.

  ## Examples

      iex> change_bookmark(bookmark)
      %Ecto.Changeset{data: %Bookmark{}}

  """
  def change_bookmark(%Bookmark{} = bookmark, attrs \\ %{}) do
    Bookmark.changeset(bookmark, attrs)
  end
end
