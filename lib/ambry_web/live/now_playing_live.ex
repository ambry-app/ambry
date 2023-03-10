defmodule AmbryWeb.NowPlayingLive do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.NowPlayingLive.Components
  import AmbryWeb.Layouts, only: [nav_header: 1]

  alias Ambry.{Media, PubSub}

  alias AmbryWeb.Player

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />

    <div class="flex h-full flex-col">
      <.nav_header user={@current_user} active_path={@nav_active_path} />

      <main class="flex grow flex-col overflow-hidden lg:flex-row">
        <%= if @player.player_state do %>
          <.media_details media={@player.player_state.media} />
          <.media_tabs user={@current_user} player={@player} />
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
      case socket.assigns.player.player_state do
        nil ->
          [page_title: "Personal Audiobook Streaming"]

        player_state ->
          [
            page_title: Media.get_media_description(player_state.media)
          ]
      end

    if connected?(socket) do
      Player.subscribe!(socket.assigns.player)
    end

    {:ok, assign(socket, assigns), layout: false}
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :player, action: :updated} = _message, socket) do
    {:noreply, assign(socket, player: Player.reload!(socket.assigns.player))}
  end
end
