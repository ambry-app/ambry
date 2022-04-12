defmodule AmbryWeb.LibraryLive.Home.RecentMedia do
  @moduledoc false

  use AmbryWeb, :p_live_component

  alias Ambry.Media

  @limit 10

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
    player_states = Map.get(assigns, :player_states, [])
    offset = Map.get(assigns, :offset, 0)

    {more_player_states, has_more?} = Media.get_recent_player_states(user.id, offset, @limit)

    player_states = player_states ++ more_player_states

    socket
    |> assign(:player_states, player_states)
    |> assign(:offset, offset + @limit)
    |> assign(:show_load_more?, has_more?)
  end
end
