defmodule Ambry.Media.Processor.M4B do
  @moduledoc """
  A media processor that converts a single M4B to dash streaming format.
  """

  import Ambry.Media.Processor.Shared

  def can_run?(media) do
    media |> files(".m4b") |> length() == 1
  end

  def run(media) do
    filename = copy!(media)
    create_mpd!(media, filename)
    finalize!(media, filename)
  end

  defp copy!(media) do
    [m4b_file] = files(media, ".m4b")
    filename = Ecto.UUID.generate()

    File.cp!(
      Path.join(media.source_path, m4b_file),
      Path.join(media.source_path, "#{filename}.mp4")
    )

    filename
  end
end
