defmodule Ambry.Media.Processor do
  @moduledoc """
  Media uploads processor.

  Delegates to other modules depending on what kind of files were uploaded.
  """

  import Ambry.Media.Processor.Shared, only: [out_path: 1]

  alias Ambry.Media
  alias Ambry.Media.Processor.{MP3, MP3Concat, MP4, MP4Concat, MP4ConcatReEncode, MP4ReEncode}

  @processors [
    MP3,
    MP3Concat,
    MP4,
    MP4Concat,
    MP4ConcatReEncode,
    MP4ReEncode
  ]

  def run!(media, processor \\ :auto) do
    {:ok, media} = Media.update_media(media, %{status: :processing}, for: :processor_update)

    try do
      ensure_clean_out_path!(media)
      run_processor!(media, processor)
    rescue
      exception ->
        {:ok, _media} = Media.update_media(media, %{status: :error}, for: :processor_update)

        reraise exception, __STACKTRACE__
    end
  end

  defp ensure_clean_out_path!(media) do
    path = out_path(media)
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
