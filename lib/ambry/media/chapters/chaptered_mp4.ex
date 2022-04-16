defmodule Ambry.Media.Chapters.ChapteredMP4 do
  @moduledoc """
  Tries to extract chapter information from multiple m4a or m4b files.
  """

  import Ambry.Media.Chapters.Utils
  import Ambry.Media.Processor.Shared

  require Logger

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Chaptered MP4s"
  end

  def available?(media) do
    media |> files(@extensions) |> length() > 1
  end

  def get_chapters(media) do
    mp4_files = files(media, @extensions)

    get_chapters(media, mp4_files)
  end

  defp get_chapters(media, files, offset \\ Decimal.new(0), acc \\ [])

  defp get_chapters(_media, [], _offset, acc), do: {:ok, Enum.reverse(acc)}

  defp get_chapters(media, [file | rest], offset, acc) do
    with {:ok, json} <- run_probe(media, file),
         {:ok, metadata} <- decode(json),
         {:ok, duration} <- get_accurate_duration(media, file),
         {:ok, title} <- get_title(metadata, file) do
      chapter = build_chapter(title, offset)
      get_chapters(media, rest, Decimal.add(offset, duration), [chapter | acc])
    end
  end

  defp run_probe(media, mp4_file) do
    command = "ffprobe"
    args = ["-i", mp4_file, "-print_format", "json", "-show_chapters", "-loglevel", "error"]

    case System.cmd(command, args, cd: source_path(media), parallelism: true) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.warn(fn -> "MP4 chapter probe failed. Code: #{code}, Output: #{output}" end)
        {:error, :probe_failed}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, chapters} ->
        {:ok, chapters}

      {:error, error} ->
        Logger.warn(fn -> "ffmpeg chapter json decode failed: #{inspect(error)}" end)
        {:error, :invalid_json}
    end
  end

  defp get_title(metadata, filename) do
    case {metadata, filename} do
      {%{"chapters" => [%{"tags" => %{"title" => title}}]}, _filename} ->
        {:ok, title}

      {_metadata, filename} ->
        {:ok, Path.rootname(filename)}
    end
  end

  defp build_chapter(title, offset) do
    %{
      title: title,
      time: Decimal.round(offset, 2)
    }
  end
end
