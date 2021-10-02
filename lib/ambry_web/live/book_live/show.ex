defmodule AmbryWeb.BookLive.Show do
  @moduledoc """
  LiveView for showing book details.
  """
  use AmbryWeb, :live_view

  alias Ambry.{Books, PubSub}
  alias AmbryWeb.BookLive.{Header, PlayButton}

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl Phoenix.LiveView
  def mount(%{"id" => book_id}, _session, socket) do
    book = Books.get_book_with_media!(book_id)

    socket =
      if connected?(socket) do
        user = socket.assigns.current_user
        browser_id = socket |> get_connect_params() |> Map.fetch!("browser_id")

        for media <- book.media do
          PubSub.sub(:playback_started, user.id, browser_id, media.id)
          PubSub.sub(:playback_paused, user.id, browser_id, media.id)
        end

        assign(socket, :browser_id, browser_id)
      else
        socket
      end

    {:ok,
     socket
     |> assign(:page_title, book.title)
     |> assign(:book, book)}
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

  def recording_type(%{abridged: true}), do: "Abridged"
  def recording_type(%{abridged: false}), do: "Unabridged"
end
