defmodule Ambry.Media.Chapters.ChapteredMP4 do
  @moduledoc """
  Tries to extract chapter information from multiple m4a or m4b files.
  """

  import Ambry.Media.Chapters.Utils

  alias Ambry.Media.Media

  require Logger

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Each MP4 is a chapter"
  end

  def available?(media) do
    media |> Media.files(@extensions) |> length() > 1
  end

  def inputs, do: []

  def get_chapters(media) do
    mp4_files = Media.files(media, @extensions)

    do_get_chapters(media, mp4_files)
  end

  defp do_get_chapters(media, files, offset \\ Decimal.new(0), acc \\ [])

  defp do_get_chapters(_media, [], _offset, acc), do: {:ok, Enum.reverse(acc)}

  defp do_get_chapters(media, [file | rest], offset, acc) do
    with {:ok, json} <- mp4_chapter_probe(media, file),
         {:ok, metadata} <- decode(json),
         {:ok, duration} <- get_accurate_duration(media, file),
         {:ok, title} <- get_title(metadata, file) do
      chapter = build_chapter(title, offset)
      do_get_chapters(media, rest, Decimal.add(offset, duration), [chapter | acc])
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, chapters} ->
        {:ok, chapters}

      {:error, error} ->
        Logger.warning(fn -> "ffmpeg chapter json decode failed: #{inspect(error)}" end)
        {:error, :invalid_json}
    end
  end

  defp get_title(metadata, filename) do
    case {metadata, filename} do
      {%{"chapters" => [%{"tags" => %{"title" => title}}]}, _filename} ->
        {:ok, title}

      {_metadata, filename} ->
        {:ok, filename |> Path.basename() |> Path.rootname()}
    end
  end

  defp build_chapter(title, offset) do
    %{
      title: title,
      time: Decimal.round(offset, 2)
    }
  end
end
