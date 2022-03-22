defmodule Ambry.Media do
  @moduledoc """
  Functions for dealing with Media.
  """

  import Ambry.FileUtils
  import Ecto.Query

  alias Ambry.Media.{Audit, Bookmark, Media, MediaFlat, PlayerState}
  alias Ambry.{PubSub, Repo}

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
    Repo.one(from m in Media, select: count(m.id))
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
  Creates a media.

  ## Examples

      iex> create_media(%{field: value})
      {:ok, %Media{}}

      iex> create_media(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_media(attrs \\ %{}) do
    %Media{}
    |> Media.changeset(attrs, for: :create)
    |> Repo.insert()
  end

  @doc """
  Updates a media.

  ## Examples

      iex> update_media(media, %{field: new_value})
      {:ok, %Media{}}

      iex> update_media(media, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_media(%Media{} = media, attrs, for: action) do
    media
    |> Media.changeset(attrs, for: action)
    |> Repo.update()
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
    case Repo.delete(media) do
      {:ok, media} ->
        delete_media_files(media)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

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
  Gets the most recent player state for a given user, if any.
  """
  def get_most_recent_player_state(user_id) do
    result =
      PlayerState
      |> where([ps], ps.user_id == ^user_id)
      |> order_by({:desc, :updated_at})
      |> limit(1)
      |> preload(^@player_state_preload)
      |> Repo.one()

    case result do
      nil ->
        :error

      %PlayerState{} = player_state ->
        {:ok, player_state}
    end
  end

  @doc """
  Creates or touches a player state for the given user and media, then
  broadcasts a message about it.
  """
  def load_and_play_media!(user_id, media_id) do
    result =
      PlayerState
      |> where([ps], ps.user_id == ^user_id and ps.media_id == ^media_id)
      |> Repo.one()

    player_state =
      case result do
        nil ->
          {:ok, player_state} = create_player_state(%{user_id: user_id, media_id: media_id})
          player_state

        %PlayerState{} = player_state ->
          player_state
          |> PlayerState.changeset(%{})
          |> Repo.update!(force: true)
      end

    PubSub.broadcast(
      "users:#{user_id}:load-and-play-media",
      {:load_and_play_media, player_state.id}
    )
  end

  @doc """
  Gets or creates a player state for the given user and media.
  """
  def get_or_create_player_state!(user_id, media_id, touch \\ false) do
    result =
      PlayerState
      |> where([ps], ps.user_id == ^user_id and ps.media_id == ^media_id)
      |> preload(^@player_state_preload)
      |> Repo.one()

    case result do
      nil ->
        {:ok, player_state} = create_player_state(%{user_id: user_id, media_id: media_id})
        Repo.preload(player_state, @player_state_preload)

      %PlayerState{} = player_state ->
        if touch do
          player_state
          |> PlayerState.changeset(%{})
          |> Repo.update!(force: true)
        else
          player_state
        end
    end
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
  Creates a player_state.

  ## Examples

      iex> create_player_state(%{field: value})
      {:ok, %PlayerState{}}

      iex> create_player_state(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_player_state(attrs \\ %{}) do
    %PlayerState{}
    |> PlayerState.changeset(attrs)
    |> Repo.insert()
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
    player_state
    |> PlayerState.changeset(attrs)
    |> Repo.update()
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
  def create_bookmark(attrs \\ %{}) do
    %Bookmark{}
    |> Bookmark.changeset(attrs)
    |> Repo.insert()
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
    bookmark
    |> Bookmark.changeset(attrs)
    |> Repo.update()
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
    Repo.delete(bookmark)
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
