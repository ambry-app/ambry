defmodule AmbryWeb.NowPlayingLive.Index do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.NowPlayingLive.Index.Components
  import AmbryWeb.Layouts, only: [nav_header: 1, flashes: 1]

  alias Ambry.Media
  alias Ambry.PubSub

  alias AmbryWeb.Player

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.flashes flash={@flash} />

    <div class="flex h-full flex-col">
      <.nav_header user={@current_user} active_path={@nav_active_path} />

      <main class="flex grow flex-col overflow-hidden lg:flex-row">
        <%= if @player_state do %>
          <.media_details media={@player_state.media} />
          <.media_tabs media={@player_state.media} user={@current_user} />
        <% else %>
          <p class="mx-auto mt-56 max-w-sm p-2 text-center text-lg">
            Welcome to Ambry! You don't have a book opened, head on over to the
            <.brand_link navigate={~p"/library"}>library</.brand_link>
            to choose something to listen to.
          </p>
        <% end %>
      </main>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    assigns =
      case socket.assigns do
        %{player_state: player_state} when is_map(player_state) ->
          [page_title: Media.get_media_description(player_state.media)]

        _else ->
          [page_title: "Personal Audiobook Streaming"]
      end

    if connected?(socket) do
      Player.subscribe_socket!(socket)
    end

    {:ok, assign(socket, assigns), layout: false}
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :player, action: :updated} = _message, socket) do
    player = Player.get_for_socket(socket)

    {:noreply, assign(socket, player_state: player.player_state)}
  end
end
