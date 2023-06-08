defmodule Ambry.Media.Chapters.MP4 do
  @moduledoc """
  Tries to extract chapter information from a single m4a or m4b file.
  """

  import Ambry.Media.Chapters.Utils

  alias Ambry.Media.Media

  require Logger

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Extract from M4B metadata"
  end

  def available?(media) do
    media |> Media.files(@extensions) |> length() == 1
  end

  def inputs, do: []

  def get_chapters(media, _params) do
    [mp4_file] = Media.files(media, @extensions)

    with {:ok, json} <- mp4_chapter_probe(media, mp4_file),
         {:ok, chapters} <- decode(json) do
      adapt_ffmpeg_chapters(chapters)
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
