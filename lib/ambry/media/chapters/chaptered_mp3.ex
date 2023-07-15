defmodule Ambry.Media.Chapters.ChapteredMP3 do
  @moduledoc """
  Extracts chapter data from a collection of individually chaptered MP3s.
  """

  import Ambry.Media.Chapters.Utils

  alias Ambry.Media.Media

  require Logger

  @extensions ~w(.mp3)

  def name do
    "Each MP3 is a chapter"
  end

  def available?(media) do
    media |> Media.files(@extensions) |> length() > 1
  end

  def inputs, do: []

  def get_chapters(media, _params) do
    mp3_files = Media.files(media, @extensions)

    do_get_chapters(media, mp3_files)
  end

  defp do_get_chapters(media, files, offset \\ Decimal.new(0), acc \\ [])

  defp do_get_chapters(_media, [], _offset, acc), do: {:ok, Enum.reverse(acc)}

  defp do_get_chapters(media, [file | rest], offset, acc) do
    with {:ok, json} <- get_metadata_json(media, file),
         {:ok, metadata} <- decode(json),
         {:ok, duration} <- get_accurate_duration(media, file),
         {:ok, title} <- get_title(metadata) do
      chapter = build_chapter(title, offset)
      do_get_chapters(media, rest, Decimal.add(offset, duration), [chapter | acc])
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

  defp get_title(metadata) do
    case metadata do
      %{"format" => %{"tags" => %{"title" => title}}} ->
        {:ok, title}

      %{"format" => %{"filename" => filename}} ->
        {:ok, Path.rootname(filename)}

      unexpected ->
        Logger.warning(fn -> "No usable title found: #{inspect(unexpected)}" end)
        {:error, :no_chapter_titles}
    end
  end

  defp build_chapter(title, offset) do
    %{
      title: title,
      time: Decimal.round(offset, 2)
    }
  end
end
