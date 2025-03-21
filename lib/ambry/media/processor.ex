defmodule Ambry.Media.Processor do
  @moduledoc """
  Media uploads processor.

  Delegates to other modules depending on what kind of files were uploaded.
  """

  alias Ambry.Media
  alias Ambry.Media.Processor.MP3
  alias Ambry.Media.Processor.MP3Concat
  alias Ambry.Media.Processor.MP4
  alias Ambry.Media.Processor.MP4Concat
  alias Ambry.Media.Processor.MP4ConcatReEncode
  alias Ambry.Media.Processor.MP4Copy
  alias Ambry.Media.Processor.MP4ReEncode
  alias Ambry.Media.Processor.OpusConcat

  @processors [
    MP3,
    MP3Concat,
    MP4,
    MP4Concat,
    MP4ConcatReEncode,
    MP4Copy,
    MP4ReEncode,
    OpusConcat
  ]

  def run!(media, processor \\ :auto) do
    {:ok, media} = Media.update_media(media, %{status: :processing})

    try do
      ensure_clean_out_path!(media)
      run_processor!(media, processor)
    rescue
      exception ->
        {:ok, _media} = Media.update_media(media, %{status: :error})

        reraise exception, __STACKTRACE__
    end
  end

  defp ensure_clean_out_path!(media) do
    path = Media.Media.out_path(media)
    File.rm_rf!(path)
    File.mkdir_p!(path)
  end

  defp run_processor!(media, processor) do
    if processor == :auto do
      case matched_processors(media) do
        [processor | _] -> processor.run(media)
        [] -> raise "No matching processor found!"
      end
    else
      processor.run(media)
    end
  end

  def matched_processors(media_or_filenames) do
    Enum.filter(@processors, fn processor ->
      processor.can_run?(media_or_filenames)
    end)
  end
end
