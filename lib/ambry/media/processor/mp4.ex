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
    filename = copy!(media)
    create_stream!(media, filename)
    finalize!(media, filename)
  end

  defp copy!(media) do
    [m4b_file] = files(media, @extensions)
    filename = Ecto.UUID.generate()

    File.cp!(
      Path.join(media.source_path, m4b_file),
      Path.join(media.source_path, "#{filename}.mp4")
    )

    filename
  end
end
