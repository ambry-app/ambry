defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc false

  use AmbryWeb, :live_view

  alias Ambry.Media

  on_mount {AmbryWeb.UserAuth, :ensure_authenticated}
  on_mount AmbryWeb.PlayerStateHooks

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div id="media-player" phx-hook="mediaPlayer" {player_state_attrs(@player_state)}>
      <audio />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(:not_mounted_at_router, _session, socket) do
    {:ok, socket, layout: false}
  end

  defp player_state_attrs(nil), do: %{"data-media-unloaded" => true}

  defp player_state_attrs(%Media.PlayerState{
         media: %Media.Media{id: id, mpd_path: path},
         position: position,
         playback_rate: playback_rate
       }) do
    %{
      "data-media-id" => id,
      "data-media-position" => position,
      "data-media-path" => "#{path}#t=#{position}",
      "data-media-playback-rate" => playback_rate
    }
  end

  @impl Phoenix.LiveView
  def handle_event("playback-time-updated", %{"playback-time" => playback_time}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        position: playback_time
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-rate-changed", %{"playback-rate" => playback_rate}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        playback_rate: playback_rate
      })

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
end
