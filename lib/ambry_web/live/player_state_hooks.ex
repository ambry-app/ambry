defmodule AmbryWeb.PlayerStateHooks do
  @moduledoc """
  LiveView lifecycle hooks for the persistent player.
  """

  alias Ambry.Media

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns.current_user

    player_state =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} -> player_state
        :error -> nil
      end

    {:cont, assign(socket, :player_state, player_state)}
  end
end
