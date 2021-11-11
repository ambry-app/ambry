defmodule Ambry.Media.Processor.MP4Concat do
  @moduledoc """
  A media processor that concatenates a collection of MP4 files and then
  converts them to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  @extensions ~w(.mp4 .m4a .m4b)

  def can_run?(media) do
    media |> files(@extensions) |> length() > 1
  end

  def run(media) do
    id = concat_mp4!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp concat_mp4!(media) do
    create_concat_text_file!(media, @extensions)

    id = get_id(media)
    command = "ffmpeg"
    args = ["-f", "concat", "-safe", "0", "-i", "files.txt", "-acodec", "copy", "#{id}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: out_path(media), parallelism: true)

    id
  end
end
