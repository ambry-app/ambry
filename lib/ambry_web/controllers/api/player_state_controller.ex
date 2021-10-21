defmodule AmbryWeb.API.PlayerStateController do
  use AmbryWeb, :controller

  import AmbryWeb.API.ControllerUtils

  alias Ambry.Media

  action_fallback AmbryWeb.FallbackController

  @limit 10

  def index(conn, params) do
    offset = offset_from_params(params, @limit)

    player_states = Media.get_recent_player_states(conn.assigns.api_user.id, offset, @limit)
    render(conn, "index.json", player_states: player_states)
  end

  def show(conn, %{"id" => media_id}) do
    player_state = Media.get_or_create_player_state!(conn.assigns.api_user.id, media_id)
    render(conn, "show.json", player_state: player_state)
  end

  def update(conn, %{"id" => media_id, "playerState" => params}) do
    player_state = Media.get_or_create_player_state!(conn.assigns.api_user.id, media_id)

    {:ok, player_state} =
      Media.update_player_state(player_state, %{
        position: params["position"],
        playback_rate: params["playbackRate"]
      })

    render(conn, "show.json", player_state: player_state)
  end
end
