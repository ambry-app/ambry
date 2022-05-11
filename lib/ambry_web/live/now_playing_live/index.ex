defmodule AmbryWeb.NowPlayingLive.Index do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.NowPlayingLive.Index.Components

  alias Ambry.Media

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    assigns =
      case socket.assigns do
        %{player_state: player_state} when is_map(player_state) ->
          [page_title: Media.get_media_description(player_state.media)]

        _else ->
          [page_title: "Personal Audiobook Streaming"]
      end

    {:ok, assign(socket, assigns), layout: false}
  end
end
