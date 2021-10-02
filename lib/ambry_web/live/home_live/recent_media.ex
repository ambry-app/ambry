defmodule AmbryWeb.HomeLive.RecentMedia do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.{Media, PubSub}
  alias AmbryWeb.Components.PlayerStateTiles

  @limit 10

  prop user, :any, required: true
  prop browser_id, :string, required: true

  data show_load_more?, :boolean, default: true
  data player_states, :list, default: []

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_player_states()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("load-more", _params, socket) do
    {:noreply, load_player_states(socket)}
  end

  defp load_player_states(%{assigns: assigns} = socket) do
    user = assigns.user
    browser_id = assigns.browser_id
    player_states = Map.get(assigns, :player_states, [])
    offset = Map.get(assigns, :offset, 0)

    more_player_states = Media.get_recent_player_states(user.id, offset, @limit)

    if browser_id do
      for player_state <- more_player_states do
        PubSub.sub(:playback_started, user.id, browser_id, player_state.media.id)
        PubSub.sub(:playback_paused, user.id, browser_id, player_state.media.id)
      end
    end

    player_states = player_states ++ more_player_states
    show_load_more? = length(more_player_states) == @limit

    socket
    |> assign(:player_states, player_states)
    |> assign(:offset, offset + @limit)
    |> assign(:show_load_more?, show_load_more?)
  end
end
