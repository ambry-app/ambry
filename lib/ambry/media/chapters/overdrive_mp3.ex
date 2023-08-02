defmodule Ambry.Media.Chapters.OverdriveMP3 do
  @moduledoc """
  Tries to extract chapter information from a set of OverDrive MP3s.
  """

  import Ambry.Media.Chapters.Utils
  import SweetXml

  alias Ambry.Media.Media

  require Logger

  @extensions ~w(.mp3)

  def name do
    "Extract from OverDrive MP3s"
  end

  def available?(media) do
    media |> Media.files(@extensions) |> length() >= 1
  end

  def inputs, do: []

  def get_chapters(media) do
    mp3_files = Media.files(media, @extensions)

    do_get_chapters(media, mp3_files)
  end

  defp do_get_chapters(media, files, offset \\ Decimal.new(0), acc \\ [])

  defp do_get_chapters(_media, [], _offset, acc), do: {:ok, acc |> Enum.reverse() |> List.flatten()}

  defp do_get_chapters(media, [file | rest], offset, acc) do
    with {:ok, json} <- get_metadata_json(media, file),
         {:ok, metadata} <- decode(json),
         {:ok, duration} <- get_accurate_duration(media, file),
         {:ok, marker_xml} <- get_marker_xml(metadata),
         {:ok, markers} <- decode_marker_xml(marker_xml) do
      chapters = build_chapters(markers, offset)
      do_get_chapters(media, rest, Decimal.add(offset, duration), [chapters | acc])
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, error} ->
        Logger.warning(fn -> "ffprobe metadata json decode failed: #{inspect(error)}" end)
        {:error, :invalid_json}
    end
  end

  defp get_marker_xml(metadata) do
    case metadata do
      %{"format" => %{"tags" => %{"OverDrive MediaMarkers" => xml}}} ->
        {:ok, xml}

      unexpected ->
        Logger.warning(fn -> "No OverDrive MediaMarkers in metadata: #{inspect(unexpected)}" end)
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
      Logger.warning(fn -> "Unexpected OverDrive MediaMarkers format: #{marker_xml}" end)
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
end
