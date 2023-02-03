defmodule AmbryWeb.PlayerStateHooks do
  @moduledoc """
  LiveView lifecycle hooks for the persistent player.
  """

  import Phoenix.Component, only: [assign: 2]

  alias AmbryWeb.Player

  require Logger

  def on_mount(:default, _params, _session, socket) do
    %{assigns: %{current_user: user}, private: private} = socket

    player = Player.get(user, private[:connect_params]["player_id"])

    {:cont, assign(socket, player: player)}
  end
end
