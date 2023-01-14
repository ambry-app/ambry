defmodule AmbryWeb.NowPlayingLive.Index do
  @moduledoc """
  LiveView for the player.
  """

  use AmbryWeb, :live_view

  import AmbryWeb.NowPlayingLive.Index.Components

  alias Ambry.Media

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div id="now-playing" class="relative flex h-screen flex-col">
      <.nav_header user={@current_user} active_path={@nav_active_path} />

      <main class="flex flex-grow flex-col overflow-hidden lg:flex-row">
        <%!-- <%= if @player_state do %>
          <.media_details media={@player_state.media} />
          <.media_tabs media={@player_state.media} user={@current_user} />
        <% else %> --%>
        <p class="mx-auto mt-56 max-w-sm p-2 text-center text-lg">
          Welcome to Ambry! You don't have a book opened, head on over to the
          <.brand_link navigate={~p"/library"}>library</.brand_link>
          to choose something to listen to.
        </p>
        <%!-- <% end %> --%>
      </main>

      <%!-- <%= if @player_state do %>
        <Amc.footer player_state={@player_state} />
      <% end %> --%>
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

    {:ok, assign(socket, assigns), layout: false}
  end
end
