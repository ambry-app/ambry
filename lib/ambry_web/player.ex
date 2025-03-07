defmodule AmbryWeb.Player do
  @moduledoc """
  Tracks player state and playback state for a connected browser session.

  Uses Phoenix Presence and PubSub to keep everything in sync.
  """

  alias Ambry.Accounts
  alias Ambry.Accounts.User
  alias Ambry.Media
  alias Ambry.PubSub
  alias AmbryWeb.Player.PubSub.PlayerUpdated
  alias AmbryWeb.Player.Tracker

  defstruct [:connected?, :id, :user, :player_state, :playback_state, :current_chapter_index]

  def new(%User{} = user) do
    new(user, nil)
  end

  def get(%User{} = user, player_id) do
    case Tracker.fetch(player_id) do
      :error -> new(user, player_id)
      {:ok, player} -> player
    end
  end

  def connect!(player) do
    player = %{player | connected?: true}
    Tracker.track!(player)
    player
  end

  defp new(user, player_id) do
    {player_state, playback_state} =
      case user.loaded_player_state_id do
        nil -> {nil, :unloaded}
        player_state_id -> {Media.get_player_state!(player_state_id), :paused}
      end

    update_current_chapter(%__MODULE__{
      connected?: false,
      id: player_id,
      user: user,
      player_state: player_state,
      playback_state: playback_state
    })
  end

  def subscribe!(%__MODULE__{id: id} = player) when is_binary(id) do
    :ok = PubSub.subscribe(PlayerUpdated.player_topic(player))
  end

  # NOTE: This might not be a great idea, we should see if we can make this not
  # blow up in tests instead.
  def subscribe!(%__MODULE__{id: nil}), do: :ok

  def reload!(%__MODULE__{id: id}) when is_binary(id) do
    case Tracker.fetch(id) do
      :error -> raise "Tried to reload unknown player: #{inspect(id)}"
      {:ok, player} -> player
    end
  end

  def playback_started(player) do
    update_tracker!(%{player | playback_state: :playing})
  end

  def playback_paused(player, position) do
    player = update_player_state!(player, %{position: position})

    update_tracker!(%{player | playback_state: :paused})
  end

  def playback_rate_changed(player, rate) do
    player |> update_player_state!(%{playback_rate: rate}) |> update_tracker!()
  end

  def playback_time_updated(player, position, persist: true) do
    player
    |> update_player_state!(%{position: position})
    |> update_current_chapter()
    |> update_tracker!()
  end

  def playback_time_updated(player, position) do
    player.player_state.position
    |> put_in(position)
    |> update_current_chapter()
    |> update_tracker!()
  end

  def load_media(player, user, media_id) do
    player_state = Media.load_player_state!(user, media_id)
    user = Accounts.get_user!(user.id)

    player = %{player | player_state: player_state, user: user}

    update_tracker!(player)
  end

  defp update_player_state!(player, attrs) do
    {:ok, player_state} = Media.update_player_state(player.player_state, attrs)
    %{player | player_state: player_state}
  end

  defp update_tracker!(player) do
    Tracker.update!(player)

    :ok =
      player
      |> PlayerUpdated.new()
      |> PubSub.broadcast()

    player
  end

  defp update_current_chapter(%{player_state: nil} = player), do: player

  defp update_current_chapter(player) do
    %{player_state: %{position: position, media: %{chapters: chapters}}} = player

    chapter_index =
      chapters
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find_value(fn {chapter, idx} ->
        if Decimal.eq?(position, chapter.time) or Decimal.gt?(position, chapter.time), do: idx
      end)

    %{player | current_chapter_index: chapter_index}
  end
end
