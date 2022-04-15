defmodule AmbryWeb.NowPlayingLive.Index do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.NowPlayingLive.Index.Components

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    assigns =
      case socket.assigns do
        %{player_state: player_state} ->
          [page_title: player_state.media.book.title]

        _else ->
          [page_title: "Personal Audiobook Streaming"]
      end

    {:ok, assign(socket, assigns), layout: false}
  end
end
