defmodule AmbryWeb.HeaderLive.Header do
  use AmbryWeb, :live_view

  alias Ambry.Media
  # alias Ambry.PubSub
  alias AmbryWeb.Components.{ChevronDown, ChevronUp}
  alias Surface.Components.LiveRedirect

  on_mount {AmbryWeb.UserLiveAuth, :ensure_mounted_current_user}

  @impl true
  def mount(:not_mounted_at_router, _session, socket) do
    user = socket.assigns.current_user

    # if connected?(socket),
    #   do: PubSub.subscribe("users:#{user.id}:load-and-play-media")

    player_state =
      case Media.get_most_recent_player_state(user.id) do
        {:ok, player_state} -> player_state
        :error -> nil
      end

    {:ok,
     socket
     |> assign(:player_state, player_state)
     |> assign(:expanded, false)}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  @impl true
  def handle_event("load-and-play-media", %{"media-id" => media_id}, socket) do
    user = socket.assigns.current_user
    player_state = Media.get_or_create_player_state!(user.id, media_id)

    {:noreply,
     socket
     |> assign(:player_state, player_state)
     |> push_event("reload-media", %{play: true})}
  end

  def handle_event("duration-loaded", %{"duration" => duration}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        duration: duration
      })

    {:noreply, assign(socket, :player_state, player_state)}
  end

  def handle_event("playback-started", _params, socket) do
    {:noreply, assign(socket, :playing, true)}
  end

  def handle_event("playback-paused", %{"playback-time" => playback_time}, socket) do
    {:ok, player_state} =
      Media.update_player_state(socket.assigns.player_state, %{
        position: playback_time
      })

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

  # # Show at least one decimal place, even if it's zero.
  # defp format_decimal(decimal) do
  #   rounded = Decimal.round(decimal, 1)

  #   if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
  # end

  # defp format_timecode(nil) do
  #   "unknown"
  # end

  # defp format_timecode(decimal_seconds) do
  #   seconds = decimal_seconds |> Decimal.round() |> Decimal.to_integer()

  #   hours = div(seconds, 3600)
  #   remainder = rem(seconds, 3600)
  #   minutes = div(remainder, 60)
  #   seconds = rem(remainder, 60)

  #   format(hours, minutes, seconds)
  # end

  # defp format(0, minutes, seconds), do: "#{minutes}:#{pad(seconds)}"
  # defp format(hours, minutes, seconds), do: "#{hours}:#{pad(minutes)}:#{pad(seconds)}"

  # defp pad(number), do: :io_lib.format('~2..0B', [number])

  # defp progress_percent(%{duration: nil}), do: "0.0"

  # defp progress_percent(%{position: position, duration: duration}) do
  #   position
  #   |> Decimal.div(duration)
  #   |> Decimal.mult(100)
  #   |> Decimal.round(1)
  #   |> Decimal.to_string()
  # end

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
