defmodule AmbryWeb.Player do
  @moduledoc """
  TODO: docs
  """

  alias Ambry.Media
  alias Ambry.PubSub

  alias AmbryWeb.Player.Tracker

  defstruct [:id, :player_state, :playback_state]

  def new_from_socket(%{assigns: %{player_state: player_state}} = socket) do
    %__MODULE__{id: id(socket), player_state: player_state, playback_state: :paused}
  end

  def get_for_socket(socket) do
    Tracker.get(id(socket))
  end

  def subscribe_socket!(socket) do
    :ok = PubSub.subscribe("player:#{id(socket)}")
  end

  def track!(player, user), do: Tracker.track!(player, user)

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
    player |> update_player_state!(%{position: position}) |> update_tracker!()
  end

  def playback_time_updated(player, position) do
    update_tracker!(put_in(player.player_state.position, position))
  end

  def load_media(player, user, media_id) do
    player_state = Media.load_player_state!(user, media_id)
    player = %{player | player_state: player_state}
    update_tracker!(player)
  end

  defp update_player_state!(player, attrs) do
    {:ok, player_state} = Media.update_player_state(player.player_state, attrs)
    %{player | player_state: player_state}
  end

  defp update_tracker!(player) do
    Tracker.update!(player)
    PubSub.broadcast_update(player)
    player
  end

  defp id(socket), do: socket.assigns.live_socket_id
end
