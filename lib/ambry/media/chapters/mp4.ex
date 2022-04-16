defmodule Ambry.Media.Chapters.MP4 do
  @moduledoc """
  Tries to extract chapter information from a single m4a or m4b file.
  """

  import Ambry.Media.Chapters.Utils
  import Ambry.Media.Processor.Shared

  require Logger

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Single MP4"
  end

  def available?(media) do
    media |> files(@extensions) |> length() == 1
  end

  def get_chapters(media) do
    with {:ok, json} <- run_probe(media),
         {:ok, chapters} <- decode(json) do
      adapt_ffmpeg_chapters(chapters)
    end
  end

  defp run_probe(media) do
    [mp4_file] = files(media, @extensions)

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
end
