defmodule Ambry.Media.Chapters.OverdriveMP3 do
  @moduledoc """
  Tries to extract chapter information from a set of OverDrive MP3s.
  """

  import Ambry.Media.Processor.Shared
  import SweetXml

  require Logger

  @extensions ~w(.mp3)

  def name do
    "OverDrive MP3s"
  end

  def available?(media) do
    media |> files(@extensions) |> length() >= 1
  end

  def get_chapters(media) do
    mp3_files = files(media, @extensions)

    get_chapters(media, mp3_files)
  end

  defp get_chapters(media, files, offset \\ Decimal.new(0), acc \\ [])

  defp get_chapters(_media, [], _offset, acc), do: {:ok, acc |> Enum.reverse() |> List.flatten()}

  defp get_chapters(media, [file | rest], offset, acc) do
    with {:ok, json} <- get_metadata_json(media, file),
         {:ok, metadata} <- decode(json),
         {:ok, duration} <- get_duration(metadata),
         {:ok, marker_xml} <- get_marker_xml(metadata),
         {:ok, markers} <- decode_marker_xml(marker_xml) do
      chapters = build_chapters(markers, offset)
      get_chapters(media, rest, Decimal.add(offset, duration), [chapters | acc])
    end
  end

  defp get_metadata_json(media, file) do
    command = "ffprobe"

    args = [
      "-i",
      file,
      "-print_format",
      "json",
      "-show_entries",
      "stream=codec_name:format",
      "-v",
      "quiet"
    ]

    case System.cmd(command, args, cd: source_path(media), parallelism: true) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.warn(fn -> "MP3 metadata probe failed. Code: #{code}, Output: #{output}" end)
        {:error, :probe_failed}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, error} ->
        Logger.warn(fn -> "ffprobe metadata json decode failed: #{inspect(error)}" end)
        {:error, :invalid_json}
    end
  end

  defp get_duration(metadata) do
    case metadata do
      %{"format" => %{"duration" => duration_string}} ->
        {:ok, Decimal.new(duration_string)}

      unexpected ->
        Logger.warn(fn -> "Missing duration in metadata: #{inspect(unexpected)}" end)
        {:error, :missing_duration}
    end
  end

  defp get_marker_xml(metadata) do
    case metadata do
      %{"format" => %{"tags" => %{"OverDrive MediaMarkers" => xml}}} ->
        {:ok, xml}

      unexpected ->
        Logger.warn(fn -> "No OverDrive MediaMarkers in metadata: #{inspect(unexpected)}" end)
        {:error, :no_overdrive_markers}
    end
  end

  defp decode_marker_xml(marker_xml) do
    markers =
      xpath(
        marker_xml,
        ~x"//Markers/Marker"l,
        name: ~x"./Name/text()"s,
        time: ~x"./Time/text()"s
      )

    if markers != [] && Enum.all?(markers, &validate_marker/1) do
      {:ok, markers}
    else
      Logger.warn(fn -> "Unexpected OverDrive MediaMarkers format: #{marker_xml}" end)
      {:error, :unexpected_xml}
    end
  end

  @timecode_regex ~r/^([0-9]+:)+[0-9]{2}(\.[0-9]+)?$/

  defp validate_marker(marker) do
    case marker do
      %{name: name, time: time} when is_binary(name) and is_binary(time) ->
        Regex.match?(@timecode_regex, time)

      _unexpected ->
        false
    end
  end

  defp build_chapters(markers, offset) do
    Enum.map(markers, fn marker ->
      %{
        title: marker.name,
        time:
          marker.time
          |> timecode_to_decimal()
          |> Decimal.add(offset)
          |> Decimal.round(2)
      }
    end)
  end

  defp timecode_to_decimal(timecode) do
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
end
