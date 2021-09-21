defmodule Ambry.Media do
  @moduledoc """
  Functions for dealing with Media.
  """

  import Ecto.Query

  alias Ambry.Media.Media
  alias Ambry.Media.PlayerState
  alias Ambry.PubSub
  alias Ambry.Repo

  @media_preload [:narrators, book: [:authors, series_books: :series]]
  @player_state_preload [media: @media_preload]

  def get_media!(media_id) do
    Repo.get!(Media, media_id)

    Media
    |> preload(^@media_preload)
    |> Repo.get!(media_id)
  end

  @doc """
  Returns a changeset for a book.
  """
  def change_media(media \\ %Media{}, params) do
    Media.changeset(media, params)
  end

  @doc """
  Creates a new media.
  """
  def create_media(params) do
    changeset = change_media(params)

    Repo.insert(changeset)
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
