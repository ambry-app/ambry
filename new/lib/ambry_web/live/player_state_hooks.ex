defmodule AmbryWeb.PlayerStateHooks do
  @moduledoc """
  LiveView lifecycle hooks for the persistent player.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Ambry.Media

  def on_mount(:default, _params, session, socket) do
    user = socket.assigns.current_user

    player_state =
      case user.loaded_player_state_id do
        nil -> nil
        id -> Media.get_player_state!(id)
      end

    {:cont, assign(socket, player_state: player_state, live_socket_id: session["live_socket_id"])}
  end
end
