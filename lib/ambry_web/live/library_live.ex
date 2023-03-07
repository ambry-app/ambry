defmodule AmbryWeb.LibraryLive do
  @moduledoc """
  LiveView for the library page.
  """

  use AmbryWeb, :live_view

  alias Ambry.PubSub

  alias AmbryWeb.LibraryLive.{RecentBooks, RecentMedia}
  alias AmbryWeb.Player

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md p-4 sm:max-w-none sm:p-10 md:max-w-screen-2xl md:p-12 lg:p-16">
      <.live_component module={RecentMedia} id="recent-media" user={@current_user} player={@player} />

      <.live_component module={RecentBooks} id="recent-books" show_admin_links?={@current_user.admin} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Player.subscribe!(socket.assigns.player)
    end

    {:ok, assign(socket, page_title: "Library")}
  end

  @impl Phoenix.LiveView
  def handle_info(%PubSub.Message{type: :player, action: :updated} = _message, socket) do
    {:noreply, assign(socket, player: Player.reload!(socket.assigns.player))}
  end
end
