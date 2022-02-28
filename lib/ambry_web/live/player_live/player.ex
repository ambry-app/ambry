defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc false

  use AmbryWeb, :p_live_view

  alias Ambry.Media

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl Phoenix.LiveView
  def mount(:not_mounted_at_router, _session, socket) do
    user = socket.assigns.current_user

    player_state =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} -> player_state
        :error -> nil
      end

    {:ok, assign(socket, :player_state, player_state), layout: false}
  end

  defp player_state_attrs(%Media.PlayerState{
         media: %Media.Media{id: id, mpd_path: path, hls_path: hls_path},
         position: position,
         playback_rate: playback_rate
       }) do
    %{
      "data-media-id" => id,
      "data-media-position" => position,
      "data-media-path" => "#{path}#t=#{position}",
      "data-media-hls-path" => "#{hls_path}#t=#{position}",
      "data-media-playback-rate" => playback_rate
    }
  end
end
