defmodule AmbryWeb.HeaderLive.Player do
  @moduledoc false

  use AmbryWeb, :live_component

  alias AmbryWeb.Components.ChevronUp
  alias Surface.Components.LiveRedirect

  prop player_state, :any, required: true
  prop playing, :boolean, required: true
  prop click, :event, required: true
  prop toggle, :event, required: true

  data show_playback_speed, :boolean, default: false

  @impl Phoenix.LiveComponent
  def handle_event("toggle-playback-speed", _params, socket) do
    {:noreply, assign(socket, :show_playback_speed, !socket.assigns.show_playback_speed)}
  end

  # Show at least one decimal place, even if it's zero.
  defp format_decimal(decimal) do
    rounded = Decimal.round(decimal, 1)

    if Decimal.equal?(rounded, decimal), do: rounded, else: decimal
  end

  defp format_timecode(nil) do
    "unknown"
  end

  defp format_timecode(decimal_seconds) do
    seconds = decimal_seconds |> Decimal.round() |> Decimal.to_integer()

    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)
    seconds = rem(remainder, 60)

    format(hours, minutes, seconds)
  end

  defp format(0, minutes, seconds), do: "#{minutes}:#{pad(seconds)}"
  defp format(hours, minutes, seconds), do: "#{hours}:#{pad(minutes)}:#{pad(seconds)}"

  defp pad(number), do: :io_lib.format('~2..0B', [number])

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
