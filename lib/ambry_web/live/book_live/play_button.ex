defmodule AmbryWeb.BookLive.PlayButton do
  @moduledoc false

  use AmbryWeb, :live_component

  alias Ambry.PubSub

  prop media, :any, required: true
  prop user, :any, required: true
  prop browser_id, :string, required: true

  data playing, :boolean, default: false

  # Public API

  def play(media_id),
    do: send_update(__MODULE__, id: media_id, playing: true)

  def pause(media_id),
    do: send_update(__MODULE__, id: media_id, playing: false)

  # Callbacks

  def update(
        %{
          media: %{id: media_id},
          user: %{id: user_id},
          browser_id: browser_id
        } = assigns,
        socket
      ) do
    playing = Ambry.PlayerStateRegistry.is_playing?(user_id, browser_id, media_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:playing, playing)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # Event handlers

  @impl Phoenix.LiveComponent
  def handle_event("play-pause", _params, socket) do
    %{
      playing: playing,
      media: %{id: media_id},
      user: %{id: user_id},
      browser_id: browser_id
    } = socket.assigns

    if playing do
      PubSub.pub(:pause, user_id, browser_id)
    else
      PubSub.pub(:load_and_play_media, user_id, browser_id, media_id)
    end

    {:noreply, socket}
  end
end
