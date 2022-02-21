defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :p_live_view

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias Ambry.Media

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    player_state =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} -> player_state
        :error -> nil
      end

    {:ok, assign(socket, :player_state, player_state)}
  end
end
