defmodule AmbryWeb.PlayerLive.Player do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :p_live_view

  import AmbryWeb.PlayerLive.Player.Components

  alias Ambry.Media

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    assigns =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} ->
          [player_state: player_state, page_title: player_state.media.book.title]

        :error ->
          [player_state: nil, page_title: "Personal Audiobook Streaming"]
      end

    {:ok, assign(socket, assigns)}
  end
end
