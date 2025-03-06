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
      MediaNarrator,
      PlayerState,
      Processor,
      ProcessorJob
    ]

  import Ambry.Utils
  import Ecto.Query

  alias Ambry.Accounts
  alias Ambry.Books
  alias Ambry.Media.Audit
  alias Ambry.Media.Bookmark
  alias Ambry.Media.Media
  alias Ambry.Media.MediaFlat
  alias Ambry.Media.PlayerState
  alias Ambry.Paths
  alias Ambry.PubSub
  alias Ambry.PubSub.BookmarkCreated
  alias Ambry.PubSub.BookmarkDeleted
  alias Ambry.PubSub.BookmarkUpdated
  alias Ambry.PubSub.MediaCreated
  alias Ambry.PubSub.MediaDeleted
  alias Ambry.PubSub.MediaUpdated
  alias Ambry.PubSub.PlayerStateUpdated
  alias Ambry.Repo
  alias Ambry.Search
  alias Ambry.Thumbnails
  alias Ambry.Thumbnails.GenerateThumbnails

  require Logger

  @media_preload [:narrators, book: [:authors, series_books: :series]]
  @player_state_preload [media: @media_preload]

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
  def get_media!(id), do: Media |> preload([:book, :media_narrators]) |> Repo.get!(id)

  @doc """
  Gets a media and the book with all its details.
  """
  def get_media_with_book_details!(id) do
    media_query =
      from m in Media, where: m.status == :ready and m.id != ^id, order_by: {:desc, :published}

    Media
    |> preload([
      :narrators,
      book: [
        :authors,
        series_books: :series,
        media: ^{media_query, [:narrators, book: [:authors, series_books: :series]]}
      ]
    ])
    |> Repo.get!(id)
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
      changeset = Media.changeset(%Media{}, attrs, for: :create)

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

      iex> update_media(media, %{field: new_value}, for: :update)
      {:ok, %Media{}}

      iex> update_media(media, %{field: bad_value}, for: :update)
      {:error, %Ecto.Changeset{}}

  """
  def update_media(%Media{} = media, attrs, for: action) do
    Repo.transact(fn ->
      changeset = Media.changeset(media, attrs, for: action)

      with {:ok, updated_media} <- Repo.update(changeset),
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
  Returns an `%Ecto.Changeset{}` for tracking media changes.

  ## Examples

      iex> change_media(media, for: :create)
      %Ecto.Changeset{data: %Media{}}

  """
  def change_media(%Media{} = media, attrs \\ %{}, opts \\ [{:for, :create}]) do
    Media.changeset(media, attrs, opts)
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

    query =
      from m in Media,
        where: m.status == :ready,
        order_by: [desc: m.inserted_at],
        offset: ^offset,
        limit: ^over_limit

    media =
      query
      |> preload(book: [:authors, series_books: :series])
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

    case update_media(media, %{thumbnails: thumbnails}, for: :thumbnails_update) do
      {:ok, updated_media} ->
        {:ok, updated_media}

      {:error, changeset} ->
        # Delete the new thumbnails from disk, because the update failed.
        Thumbnails.try_delete_thumbnails(thumbnails)

        {:error, changeset}
    end
  end

  @doc """
  Gets recent player states for a given user.
  """
  def get_recent_player_states(user_id, offset \\ 0, limit \\ 10) do
    over_limit = limit + 1

    player_states =
      PlayerState
      |> where([ps], ps.user_id == ^user_id and ps.status == :in_progress)
      |> order_by({:desc, :updated_at})
      |> offset(^offset)
      |> limit(^over_limit)
      |> preload(^@player_state_preload)
      |> Repo.all()

    player_states_to_return = Enum.slice(player_states, 0, limit)

    {player_states_to_return, player_states != player_states_to_return}
  end

  @doc """
  Gets or creates a player state for the given user and media, and marks it as
  the user's loaded player state.
  """
  def load_player_state!(user, media_id) do
    {:ok, player_state} =
      Repo.transact(fn ->
        player_state = get_player_state!(user.id, media_id)
        {:ok, _user} = Accounts.update_user_loaded_player_state(user, player_state.id)

        {:ok, player_state}
      end)

    player_state
  end

  @doc """
  Gets a single player_state.

  Raises `Ecto.NoResultsError` if the Player state does not exist.

  ## Examples

      iex> get_player_state!(123)
      %PlayerState{}

      iex> get_player_state!(456)
      ** (Ecto.NoResultsError)

  """
  def get_player_state!(id) do
    PlayerState
    |> preload(^@player_state_preload)
    |> Repo.get!(id)
  end

  @doc """
  Gets a player_state for the given user and media.

  If the player_state does not exist, it will be created.
  """
  def get_player_state!(user_id, media_id) when is_integer(user_id) and is_integer(media_id) do
    %PlayerState{user_id: user_id, media_id: media_id}
    |> Repo.insert!(
      on_conflict: {:replace, [:position, :playback_rate, :status]},
      conflict_target: [:user_id, :media_id],
      returning: true
    )
    |> Repo.preload(@player_state_preload)
  end

  @doc """
  Updates a player_state.

  ## Examples

      iex> update_player_state(player_state, %{field: new_value})
      {:ok, %PlayerState{}}

      iex> update_player_state(player_state, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_player_state(%PlayerState{} = player_state, attrs) do
    Repo.transact(fn ->
      changeset = PlayerState.changeset(player_state, attrs)

      with {:ok, updated_player_state} <- Repo.update(changeset),
           {:ok, _job} <- broadcast_player_state_updated(updated_player_state) do
        {:ok, updated_player_state}
      end
    end)
  end

  defp broadcast_player_state_updated(%PlayerState{} = player_state) do
    player_state
    |> PlayerStateUpdated.new()
    |> PubSub.broadcast_async()
  end

  @doc """
  Updates a player state for a user and media.

  If the player state does not exist, it will be created.
  """
  def update_player_state(user_id, media_id, position, playback_rate) do
    Repo.transact(fn ->
      changeset =
        PlayerState.changeset(
          %PlayerState{user_id: user_id, media_id: media_id},
          %{position: position, playback_rate: playback_rate}
        )

      options = [
        on_conflict: {:replace, [:position, :playback_rate, :status]},
        conflict_target: [:user_id, :media_id],
        returning: true
      ]

      with {:ok, player_state} <- Repo.insert(changeset, options),
           {:ok, _job} <- broadcast_player_state_updated(player_state) do
        {:ok, player_state}
      end
    end)
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

  @doc """
  Returns a description of a media containing the book's title, narrator names, and author names.
  """
  def get_media_description(%Media{} = media) do
    %{book: book, narrators: narrators} = Repo.preload(media, [:book, :narrators])
    narrators = Enum.map_join(narrators, ", ", & &1.name)

    "#{Books.get_book_description(book)} • narrated by #{narrators}"
  end
end
