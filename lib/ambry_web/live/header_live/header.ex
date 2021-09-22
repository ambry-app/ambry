defmodule AmbryWeb.HeaderLive.Header do
  use AmbryWeb, :live_view

  alias Ambry.Media
  alias Ambry.PubSub
  alias AmbryWeb.Components.{ChevronDown, ChevronUp}
  alias AmbryWeb.HeaderLive.{PlayButton, Player}
  alias Surface.Components.LiveRedirect

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(:not_mounted_at_router, _session, socket) do
    user = socket.assigns.current_user

    socket =
      if connected?(socket) do
        browser_id = socket |> get_connect_params() |> Map.fetch!("browser_id")
        PubSub.sub(:load_and_play_media, user.id, browser_id)
        PubSub.sub(:pause, user.id, browser_id)

        assign(socket, :browser_id, browser_id)
      else
        socket
      end

    player_state =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} -> player_state
        :error -> nil
      end

    {:ok,
     socket
     |> assign(:playing, false)
     |> assign(:player_state, player_state)
     |> assign(:expanded, false)}
  end

  @impl true
  def handle_info({:load_and_play_media, media_id}, socket) do
    user = socket.assigns.current_user
    player_state = Media.get_or_create_player_state!(user.id, media_id)

    # notify any subscribers that the old media is about to be paused.
    # due to race-conditions, we can't rely on the client sending us the paused
    # event.
    case socket.assigns do
      %{player_state: %{media: media}, browser_id: browser_id} ->
        PubSub.pub(:playback_paused, user.id, browser_id, media.id)

      _else ->
        :noop
    end

    {:noreply,
     socket
     |> assign(:playing, false)
     |> assign(:player_state, player_state)
     |> push_event("reload-media", %{play: true})}
  end

  def handle_info(:pause, socket) do
    {:noreply, push_event(socket, "pause", %{})}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  def handle_event("play-pause", _params, socket) do
    if socket.assigns.playing do
      {:noreply, push_event(socket, "pause", %{})}
    else
      {:noreply, push_event(socket, "play", %{})}
    end
  end

  @impl true
  def handle_event("duration-loaded", %{"duration" => duration}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        duration: duration
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-started", _params, socket) do
    %{current_user: user, player_state: %{media: media}, browser_id: browser_id} = socket.assigns
    PubSub.pub(:playback_started, user.id, browser_id, media.id)

    {:noreply, assign(socket, :playing, true)}
  end

  def handle_event("playback-paused", %{"playback-time" => playback_time}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        position: playback_time
      })

    %{current_user: user, player_state: %{media: media}, browser_id: browser_id} = socket.assigns
    PubSub.pub(:playback_paused, user.id, browser_id, media.id)

    {:noreply,
     socket
     |> assign(:player_state, player_state)
     |> assign(:playing, false)}
  end

  def handle_event("playback-rate-changed", %{"playback-rate" => playback_rate}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        playback_rate: playback_rate
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-time-updated", %{"playback-time" => playback_time}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        position: playback_time
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  defp player_state_attrs(nil), do: %{}

  defp player_state_attrs(%Media.PlayerState{
         media: %Media.Media{id: id, path: path},
         position: position,
         playback_rate: playback_rate
       }) do
    %{
      "data-media-id" => id,
      "data-media-path" => "#{path}#t=#{position}",
      "data-media-playback-rate" => playback_rate
    }
  end
end
