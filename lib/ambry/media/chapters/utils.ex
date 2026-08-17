defmodule Ambry.Media.Chapters.Utils do
  @moduledoc """
  Reading ffprobe's chapter JSON.

  `Ambry.Media.Scanner.Probe` asks ffprobe for a file's chapters; this is
  the shape-checking it hands the answer to.
  """

  require Logger

  def adapt_ffmpeg_chapters(map) do
    case map do
      %{"chapters" => [_ | _] = chapters} ->
        map_chapters(chapters)

      %{"chapters" => []} ->
        {:error, :no_chapters}

      unexpected ->
        Logger.warning(fn -> "Unexpected chapters format: #{inspect(unexpected)}" end)
        {:error, :unexpected_format}
    end
  end

  defp map_chapters(chapters, acc \\ [])

  defp map_chapters([], acc), do: {:ok, Enum.reverse(acc)}

  defp map_chapters([chapter | rest], acc) do
    case chapter do
      %{
        "start_time" => start_time_string,
        "tags" => %{"title" => title}
      } ->
        map_chapters(rest, [
          %{
            time:
              start_time_string
              |> Decimal.new()
              |> Decimal.round(2),
            title: title
          }
          | acc
        ])

      unexpected ->
        Logger.warning(fn -> "Unexpected chapter format: #{inspect(unexpected)}" end)
        {:error, :unexpected_format}
    end
  end
end
