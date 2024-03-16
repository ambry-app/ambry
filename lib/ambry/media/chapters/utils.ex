defmodule Ambry.Media.Chapters.Utils do
  @moduledoc """
  Utility functions for chapter strategies.
  """

  alias Ambry.Media.Media

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

  @doc """
  Get json metadata from a media file.
  """
  def get_metadata_json(media, file) do
    command = "ffprobe"

    args = [
      "-i",
      file,
      "-print_format",
      "json",
      "-show_entries",
      "format",
      "-v",
      "quiet"
    ]

    Logger.info(fn -> "Running `#{command} #{Enum.join(args, " ")}`" end)

    case System.cmd(command, args, cd: Media.source_path(media), parallelism: true) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.warning(fn -> "ffmpeg metadata probe failed. Code: #{code}, Output: #{output}" end)
        {:error, :probe_failed}
    end
  end

  @doc """
  Slow but accurate duration of a given file.
  """
  def get_accurate_duration(media, file) do
    command = "ffmpeg"

    args = [
      "-i",
      file,
      "-vn",
      "-stats",
      "-v",
      "quiet",
      "-f",
      "null",
      "-"
    ]

    try do
      Logger.info(fn -> "Running `#{command} #{Enum.join(args, " ")}`" end)

      {output, 0} =
        System.cmd(command, args,
          cd: Media.source_path(media),
          parallelism: true,
          stderr_to_stdout: true
        )

      timecode =
        output
        |> String.split("\r")
        |> List.last()
        |> String.trim()
        |> String.split(" ")
        |> Enum.at(1)
        |> String.split("=")
        |> Enum.at(1)

      {:ok, timecode_to_decimal(timecode)}
    rescue
      error in RuntimeError ->
        Logger.warning(fn -> "Couldn't get duration:" end)
        Logger.error(Exception.format(:error, error, __STACKTRACE__))

        {:error, :no_duration}
    end
  end

  @doc """
  Converts timecodes, e.g. `00:29:22.24` into a Decimal number of seconds.
  """
  def timecode_to_decimal(timecode) do
    case String.split(timecode, ":") do
      [minutes, seconds] ->
        seconds_of_minutes = minutes |> Decimal.new() |> Decimal.mult(60)
        seconds = Decimal.new(seconds)
        Decimal.add(seconds_of_minutes, seconds)

      [hours, minutes, seconds] ->
        seconds_of_hours = hours |> Decimal.new() |> Decimal.mult(3600)
        seconds_of_minutes = minutes |> Decimal.new() |> Decimal.mult(60)
        seconds = Decimal.new(seconds)
        seconds_of_hours |> Decimal.add(seconds_of_minutes) |> Decimal.add(seconds)
    end
  end

  def mp4_chapter_probe(media, mp4_file) do
    command = "ffprobe"
    args = ["-i", mp4_file, "-print_format", "json", "-show_chapters", "-loglevel", "error"]

    Logger.info(fn -> "Running `#{command} #{Enum.join(args, " ")}`" end)

    case System.cmd(command, args, cd: Media.source_path(media), parallelism: true) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.warning(fn -> "MP4 chapter probe failed. Code: #{code}, Output: #{output}" end)
        {:error, :probe_failed}
    end
  end
end
