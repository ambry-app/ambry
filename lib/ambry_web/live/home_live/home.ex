defmodule AmbryWeb.HomeLive.Home do
  @moduledoc """
  LiveView for the home page.
  """

  use AmbryWeb, :live_view

  alias Ambry.PubSub
  alias AmbryWeb.BookLive.PlayButton
  alias AmbryWeb.HomeLive.{RecentBooks, RecentMedia}

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        browser_id = socket |> get_connect_params() |> Map.fetch!("browser_id")

        assign(socket, :browser_id, browser_id)
      else
        socket
      end

    {:ok, assign(socket, :page_title, "Personal Audiobook Streaming")}
  end

  @impl Phoenix.LiveView
  def handle_info({:playback_started, media_id}, socket) do
    PlayButton.play(media_id)
    {:noreply, socket}
  end

  def handle_info({:playback_paused, media_id}, socket) do
    PlayButton.pause(media_id)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("play-pause", %{"media_id" => media_id}, socket) do
    user = socket.assigns.current_user
    browser_id = socket.assigns.browser_id
    playing = Ambry.PlayerStateRegistry.is_playing?(user.id, browser_id, media_id)

    if playing do
      PubSub.pub(:pause, user.id, browser_id)
    else
      PubSub.pub(:load_and_play_media, user.id, browser_id, media_id)
    end

    {:noreply, socket}
  end
end
