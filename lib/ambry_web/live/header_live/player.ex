defmodule AmbryWeb.HeaderLive.Player do
  @moduledoc false

  use AmbryWeb, :live_component

  import AmbryWeb.TimeUtils, only: [format_timecode: 1]

  alias AmbryWeb.Components.ChevronUp
  alias AmbryWeb.HeaderLive.Bookmarks
  alias Surface.Components.LiveRedirect

  prop player_state, :any, required: true
  prop playing, :boolean, required: true
  prop click, :event, required: true
  prop toggle, :event, required: true

  data show_playback_speed, :boolean, default: false
  data show_bookmarks, :boolean, default: false

  @impl Phoenix.LiveComponent
  def handle_event("toggle-playback-speed", _params, socket) do
    {:noreply, assign(socket, :show_playback_speed, !socket.assigns.show_playback_speed)}
  end

  def handle_event("toggle-bookmarks", _params, socket) do
    {:noreply, assign(socket, :show_bookmarks, !socket.assigns.show_bookmarks)}
  end

  # Show at least one decimal place, even if it's zero.
  defp format_decimal(decimal) do
    rounded = Decimal.round(decimal, 1)

    if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
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
