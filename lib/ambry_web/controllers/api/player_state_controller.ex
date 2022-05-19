defmodule AmbryWeb.API.PlayerStateController do
  use AmbryWeb, :controller

  import AmbryWeb.API.ControllerUtils

  alias Ambry.Media

  @limit 25

  def index(conn, params) do
    offset = offset_from_params(params, @limit)

    {player_states, has_more?} =
      Media.get_recent_player_states(conn.assigns.api_user.id, offset, @limit)

    render(conn, "index.json", player_states: player_states, has_more?: has_more?)
  end

  def show(conn, %{"id" => media_id}) do
    player_state = Media.get_or_create_player_state!(conn.assigns.api_user.id, media_id)
    render(conn, "show.json", player_state: player_state)
  end

  def update(conn, %{"id" => media_id, "playerState" => params}) do
    player_state = Media.get_or_create_player_state!(conn.assigns.api_user.id, media_id)

    attrs =
      Enum.reduce(params, %{}, fn
        {"position", position}, acc -> Map.put(acc, :position, position)
        {"playbackRate", rate}, acc -> Map.put(acc, :playback_rate, rate)
        _ignore, acc -> acc
      end)

    {:ok, player_state} = Media.update_player_state(player_state, attrs)

    render(conn, "show.json", player_state: player_state)
  end
end
