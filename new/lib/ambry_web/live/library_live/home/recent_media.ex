defmodule AmbryWeb.LibraryLive.Home.RecentMedia do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.Media

  # assuming this will load "all" recent books for most users, and hopefully
  # most users don't start and abandon that many books
  @limit 100

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <%= if @player_states != [] do %>
        <div class="mb-16 sm:mb-24 lg:mb-32">
          <.section_header>
            Continue listening
          </.section_header>

          <.player_state_tiles
            player_states={@player_states}
            show_load_more={@show_load_more?}
            load_more={{"load-more", @myself}}
            user={@user}
            player={@player}
          />
        </div>
      <% end %>
    </div>
    """
  end

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
