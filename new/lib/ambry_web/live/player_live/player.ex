defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc false

  use AmbryWeb, :live_view

  import AmbryWeb.Layouts

  alias AmbryWeb.Player

  on_mount {AmbryWeb.UserAuth, :ensure_authenticated}
  on_mount AmbryWeb.PlayerStateHooks

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.footer :if={@player.player_state} player={@player} />
    """
  end

  @impl Phoenix.LiveView
  def mount(:not_mounted_at_router, _session, socket) do
    socket =
      if connected?(socket) do
        assign(socket, player: Player.connect!(socket.assigns.player))
      else
        socket
      end

    {:ok, socket, layout: false}
  end

  @impl Phoenix.LiveView
  def handle_event("playback-started", _params, socket) do
    {:noreply, update(socket, :player, &Player.playback_started/1)}
  end

  def handle_event("playback-paused", %{"playback-time" => playback_time}, socket) do
    {:noreply, update(socket, :player, &Player.playback_paused(&1, playback_time))}
  end

  def handle_event("playback-rate-changed", %{"playback-rate" => playback_rate}, socket) do
    {:noreply, update(socket, :player, &Player.playback_rate_changed(&1, playback_rate))}
  end

  def handle_event(
        "playback-time-updated",
        %{"playback-time" => playback_time, "persist" => true},
        socket
      ) do
    {:noreply,
     update(socket, :player, &Player.playback_time_updated(&1, playback_time, persist: true))}
  end

  def handle_event("playback-time-updated", %{"playback-time" => playback_time}, socket) do
    {:noreply, update(socket, :player, &Player.playback_time_updated(&1, playback_time))}
  end

  def handle_event("load-media", %{"media-id" => media_id}, socket) do
    %{current_user: user} = socket.assigns

    {:noreply,
     socket
     |> update(:player, &Player.load_media(&1, user, media_id))
     |> push_event("reload-media", %{})}
  end
end
