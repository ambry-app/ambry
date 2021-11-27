defmodule Ambry.Media.Processor.MP4ReEncode do
  @moduledoc """
  A media processor that re-encodes and converts a single MP4 to dash & hls
  streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Single MP4 Re-encode"
  end

  def can_run?(%Media{} = media) do
    media |> files(@extensions) |> length() == 1
  end

  def can_run?(filenames) when is_list(filenames) do
    filenames |> filter_filenames(@extensions) |> length() == 1
  end

  def run(media) do
    id = convert_mp4!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp convert_mp4!(media) do
    [mp4_file] = files(media, @extensions)
    id = get_id(media)
    command = "ffmpeg"
    args = ["-i", "../#{mp4_file}", "-vn", "#{id}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: out_path(media), parallelism: true)

    id
  end
end
