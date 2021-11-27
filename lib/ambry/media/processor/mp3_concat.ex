defmodule Ambry.Media.Processor.MP3Concat do
  @moduledoc """
  A media processor that concatenates a collection of MP3 files and then
  converts them to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp3)

  def name do
    "MP3 Concat"
  end

  def can_run?(%Media{} = media) do
    media |> files(@extensions) |> length() > 1
  end

  def can_run?(filenames) when is_list(filenames) do
    filenames |> filter_filenames(@extensions) |> length() > 1
  end

  def run(media) do
    id = concat_mp3!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp concat_mp3!(media) do
    create_concat_text_file!(media, @extensions)

    id = get_id(media)
    command = "ffmpeg"
    args = ["-f", "concat", "-safe", "0", "-i", "files.txt", "#{id}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: out_path(media), parallelism: true)

    id
  end
end
