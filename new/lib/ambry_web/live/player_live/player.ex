defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc false

  use AmbryWeb, :live_view

  import AmbryWeb.Layouts

  alias Ambry.Media

  on_mount {AmbryWeb.UserAuth, :ensure_authenticated}
  on_mount AmbryWeb.PlayerStateHooks

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.footer playback_state={@playback_state} player_state={@player_state} />
    """
  end

  @impl Phoenix.LiveView
  def mount(:not_mounted_at_router, _session, socket) do
    socket = assign(socket, playback_state: :paused)
    {:ok, socket, layout: false}
  end

  @impl Phoenix.LiveView
  def handle_event("playback-started", _params, socket) do
    {:noreply, assign(socket, :playback_state, :playing)}
  end

  def handle_event("playback-paused", %{"playback-time" => playback_time}, socket) do
    player_state = update_player_state!(socket.assigns.player_state, %{position: playback_time})

    {:noreply, assign(socket, player_state: player_state, playback_state: :paused)}
  end

  def handle_event("playback-rate-changed", %{"playback-rate" => playback_rate}, socket) do
    player_state =
      update_player_state!(socket.assigns.player_state, %{playback_rate: playback_rate})

    {:noreply, assign(socket, player_state: player_state)}
  end

  def handle_event(
        "playback-time-updated",
        %{"playback-time" => playback_time, "persist" => true},
        socket
      ) do
    player_state = update_player_state!(socket.assigns.player_state, %{position: playback_time})

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-time-updated", %{"playback-time" => playback_time}, socket) do
    player_state = %{socket.assigns.player_state | position: playback_time}

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("load-media", %{"media-id" => media_id}, socket) do
    %{current_user: user} = socket.assigns
    player_state = Media.load_player_state!(user, media_id)

    {:noreply,
     socket
     |> assign(:player_state, player_state)
     |> push_event("reload-media", %{})}
  end

  defp update_player_state!(player_state, attrs) do
    {:ok, player_state} = Media.update_player_state(player_state, attrs)
    player_state
  end
end
