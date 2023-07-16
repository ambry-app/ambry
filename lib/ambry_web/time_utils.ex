defmodule AmbryWeb.TimeUtils do
  @moduledoc """
  Utility functions for formatting times and durations.
  """

  @doc """
  Takes a decimal number of seconds and outputs a string of the form hh:mm:ss.
  """
  def format_timecode(nil), do: nil

  def format_timecode(decimal_seconds) do
    seconds = decimal_seconds |> Decimal.round() |> Decimal.to_integer()

    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)
    seconds = rem(remainder, 60)

    format(hours, minutes, seconds)
  end

  defp format(0, minutes, seconds), do: "#{minutes}:#{pad(seconds)}"
  defp format(hours, minutes, seconds), do: "#{hours}:#{pad(minutes)}:#{pad(seconds)}"

  defp pad(number), do: :io_lib.format(~c"~2..0B", [number])

  @doc """
  Formats a decimal number of seconds into a human readable string.
  """
  def duration_display(nil), do: nil

  def duration_display(duration) do
    seconds = duration |> Decimal.round() |> Decimal.to_integer()

    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)

    if hours == 0 do
      "#{minutes} minutes"
    else
      "#{hours} hours and #{minutes} minutes"
    end
  end
end
