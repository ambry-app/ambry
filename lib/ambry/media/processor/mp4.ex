defmodule Ambry.Media.Processor.MP4 do
  @moduledoc """
  A media processor that converts a single MP4 to dash streaming format.
  """

  import Ambry.Media.Processor.Shared

  @extensions ~w(.mp4 .m4a .m4b)

  def can_run?(media) do
    media |> files(@extensions) |> length() == 1
  end

  def run(media) do
    id = copy!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp copy!(media) do
    [mp4_file] = files(media, @extensions)
    id = get_id(media)

    File.cp!(
      source_path(media, mp4_file),
      out_path(media, "#{id}.mp4")
    )

    id
  end
end
