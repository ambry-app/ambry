defmodule Ambry.Media.Processor.MP3 do
  @moduledoc """
  A media processor that converts a single MP3 to dash streaming format.
  """

  import Ambry.Media.Processor.Shared

  def can_run?(media) do
    media |> mp3_files() |> length() == 1
  end

  def run(media) do
    filename = convert_mp3!(media)
    create_mpd!(media, filename)
    finalize!(media, filename)
  end

  defp convert_mp3!(media) do
    [mp3_file] = mp3_files(media)
    filename = Ecto.UUID.generate()
    command = "ffmpeg"
    args = ["-i", mp3_file, "-vn", "#{filename}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: media.source_path, parallelism: true)

    filename
  end
end
