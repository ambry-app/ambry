defmodule Ambry.Media.Processor.MP3 do
  @moduledoc """
  A media processor that converts a single MP3 to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  @extensions ~w(.mp3)

  def can_run?(media) do
    media |> files(@extensions) |> length() == 1
  end

  def run(media) do
    id = convert_mp3!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp convert_mp3!(media) do
    [mp3_file] = files(media, @extensions)
    id = get_id(media)
    command = "ffmpeg"
    args = ["-i", "../#{mp3_file}", "-vn", "#{id}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: out_path(media), parallelism: true)

    id
  end
end
