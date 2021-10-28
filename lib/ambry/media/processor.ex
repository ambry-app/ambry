defmodule Ambry.Media.Processor do
  @moduledoc """
  Media uploads processor.

  Delegates to other modules depending on what kind of files were uploaded.
  """

  import Ambry.Media.Processor.Shared, only: [out_path: 1]

  alias Ambry.Media
  alias Ambry.Media.Processor.{MP3, MP3Concat, MP4, MP4Concat}

  @processors [
    MP3,
    MP3Concat,
    MP4,
    MP4Concat
  ]

  def run!(media) do
    {:ok, media} = Media.update_media(media, %{status: :processing}, for: :processor_update)

    try do
      ensure_out_path!(media)
      run_processor!(media)
    rescue
      exception ->
        {:ok, _media} = Media.update_media(media, %{status: :error}, for: :processor_update)

        reraise exception, __STACKTRACE__
    end
  end

  defp ensure_out_path!(media) do
    media |> out_path() |> File.mkdir_p!()
  end

  defp run_processor!(media) do
    case matched_processors(media) do
      [processor] -> processor.run(media)
      [] -> raise "No matching processor found!"
      [_ | _] -> raise "Multiple matching processors found!"
    end
  end

  defp matched_processors(media) do
    Enum.filter(@processors, fn processor ->
      processor.can_run?(media)
    end)
  end
end
