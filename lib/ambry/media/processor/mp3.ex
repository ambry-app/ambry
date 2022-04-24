defmodule Ambry.Media.Processor.MP3 do
  @moduledoc """
  A media processor that converts a single MP3 to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media

  @extensions ~w(.mp3)

  def name do
    "Single MP3"
  end

  def can_run?({media, filenames}) do
    can_run?(Media.files(media, @extensions) ++ filenames)
  end

  def can_run?(%Media{} = media) do
    media |> Media.files(@extensions) |> can_run?()
  end

  def can_run?(filenames) when is_list(filenames) do
    filenames |> filter_filenames(@extensions) |> length() == 1
  end

  def run(media) do
    id = convert_mp3!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp convert_mp3!(media) do
    [mp3_file] = Media.files(media, @extensions)
    id = Media.output_id(media)
    command = "ffmpeg"
    args = ["-i", "../#{mp3_file}", "-vn", "#{id}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: Media.out_path(media), parallelism: true)

    id
  end
end
