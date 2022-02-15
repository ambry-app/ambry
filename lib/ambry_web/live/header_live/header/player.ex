defmodule AmbryWeb.HeaderLive.Header.Player do
  @moduledoc false

  use AmbryWeb, :p_live_component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]
  import AmbryWeb.HeaderLive.Header.Player.Components

  alias AmbryWeb.HeaderLive.Header.Player.Bookmarks

  # prop player_state, :any, required: true
  # prop playing, :boolean, required: true
  # prop click, :event, required: true
  # prop toggle, :event, required: true

  # data show_playback_rate, :boolean, default: false
  # data show_bookmarks, :boolean, default: false
  # data show_chapters, :boolean, default: false

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket, %{
       show_playback_rate: false,
       show_bookmarks: false,
       show_chapters: false
     })}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-playback-speed", _params, socket) do
    {:noreply, assign(socket, :show_playback_rate, !socket.assigns.show_playback_rate)}
  end

  def handle_event("toggle-bookmarks", _params, socket) do
    {:noreply, assign(socket, :show_bookmarks, !socket.assigns.show_bookmarks)}
  end

  def handle_event("toggle-chapters", _params, socket) do
    {:noreply, assign(socket, :show_chapters, !socket.assigns.show_chapters)}
  end

  defp progress_percent(%{position: position, media: %{duration: duration}}) do
    position
    |> Decimal.div(duration)
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  defp time_left(%{position: position, playback_rate: playback_rate, media: %{duration: duration}}) do
    Decimal.div(Decimal.sub(duration, position), playback_rate)
  end
end
