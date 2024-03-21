defmodule AmbryWeb.ShelfLive do
  @moduledoc """
  LiveView for the "your shelf" page.
  """

  use AmbryWeb, :live_view

  alias Ambry.Media
  alias Ambry.PubSub
  alias AmbryWeb.Player

  @per_page 36

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none sm:p-10 md:max-w-screen-2xl md:p-12 lg:p-16">
      <%= if @empty? do %>
        <div class="mt-10">
          <FA.icon name="book-bookmark" class="mx-auto h-24 w-24 fill-current" />

          <p class="mt-4 text-center">
            Your shelf is empty! Head on over to the
            <.brand_link navigate={~p"/library"}>library</.brand_link>
            to pick a book.
          </p>
        </div>
      <% else %>
        <.player_state_tiles_stream
          id="player-states"
          stream={@streams.player_states}
          player={@player}
          page={@page}
          end?={@end?}
        />
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Player.subscribe!(socket.assigns.player)
    end

    {:ok,
     socket
     |> assign(page_title: "Your Shelf", page: 1, empty?: false)
     |> paginate_player_states(1)}
  end

  @impl Phoenix.LiveView
  def handle_event("next-page", _, socket) do
    {:noreply, paginate_player_states(socket, socket.assigns.page + 1)}
  end

  def handle_event("prev-page", %{"_overran" => true}, socket) do
    {:noreply, paginate_player_states(socket, 1)}
  end

  def handle_event("prev-page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, paginate_player_states(socket, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  defp paginate_player_states(socket, new_page) when new_page >= 1 do
    %{page: current_page, current_user: user} = socket.assigns

    {player_states, more?} =
      Media.get_recent_player_states(user.id, (new_page - 1) * @per_page, @per_page)

    {player_states, at, limit} =
      if new_page >= current_page do
        {player_states, -1, @per_page * 3 * -1}
      else
        {Enum.reverse(player_states), 0, @per_page * 3}
      end

    case player_states do
      [] ->
        assign(socket, end?: at == -1, empty?: new_page == 1)

      [_ | _] = player_states ->
        socket
        |> assign(end?: at == -1 && !more?, page: new_page)
        |> stream(:player_states, player_states, at: at, limit: limit)
    end
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :player, action: :updated} = _message, socket) do
    player = Player.reload!(socket.assigns.player)

    {:noreply,
     socket
     |> assign(player: player)
     |> stream_insert(:player_states, player.player_state)}
  end
end
