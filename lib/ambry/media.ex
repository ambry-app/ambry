defmodule Ambry.Media do
  @moduledoc """
  Functions for dealing with Media.
  """

  import Ecto.Query

  alias Ambry.Media.{Media, PlayerState}
  alias Ambry.{PubSub, Repo}

  @media_preload [:narrators, book: [:authors, series_books: :series]]
  @player_state_preload [media: @media_preload]

  @doc """
  Returns a limited list of media and whether or not there are more.

  By default, it will limit to the first 10 results. Supply `offset` and `limit`
  to change this. Also can optionally filter by the given `filter` string.

  ## Examples

      iex> list_media()
      {[%Media{}, ...], true}

  """
  def list_media(offset \\ 0, limit \\ 10, filter \\ nil) do
    over_limit = limit + 1

    query =
      from m in Media,
        offset: ^offset,
        limit: ^over_limit,
        join: b in assoc(m, :book),
        order_by: b.title,
        preload: [book: b, media_narrators: [:narrator]]

    query =
      if filter do
        title_query = "%#{filter}%"

        from [m, b] in query, where: ilike(b.title, ^title_query)
      else
        query
      end

    media = Repo.all(query)
    media_to_return = Enum.slice(media, 0, limit)

    {media_to_return, media != media_to_return}
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
  def get_media!(id), do: Media |> preload([:media_narrators]) |> Repo.get!(id)

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
      {:ok, %Media{}}

      iex> delete_media(media)
      {:error, %Ecto.Changeset{}}

  """
  def delete_media(%Media{} = media) do
    Repo.delete(media)
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
    PlayerState
    |> where([ps], ps.user_id == ^user_id)
    |> order_by({:desc, :updated_at})
    |> offset(^offset)
    |> limit(^limit)
    |> preload(^@player_state_preload)
    |> Repo.all()
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
  def get_or_create_player_state!(user_id, media_id) do
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
        player_state
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
end
