defmodule AmbryWeb.PlayerStateHooks do
  @moduledoc """
  LiveView lifecycle hooks for the persistent player.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [get_connect_params: 1]

  alias AmbryWeb.Player

  require Logger

  def on_mount(:default, _params, _session, socket) do
    %{assigns: %{current_user: user}} = socket

    player =
      case get_connect_params(socket) do
        %{"player_id" => player_id} -> Player.get(user, player_id)
        _ -> Player.new(user)
      end

    {:cont, assign(socket, player: player)}
  end
end
