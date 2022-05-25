defmodule Ambry.Media.Processor.MP3Concat do
  @moduledoc """
  A media processor that concatenates a collection of MP3 files and then
  converts them to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media
  alias Ambry.Media.Processor.ProgressTracker

  @extensions ~w(.mp3)

  def name do
    "MP3 Concat"
  end

  def can_run?({media, filenames}) do
    can_run?(Media.files(media, @extensions) ++ filenames)
  end

  def can_run?(%Media{} = media) do
    media |> Media.files(@extensions) |> can_run?()
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

    id = Media.output_id(media)
    progress_file_path = "#{id}.progress"

    {:ok, _progress_tracker} = ProgressTracker.start_link(media, progress_file_path, @extensions)

    command = "ffmpeg"

    args = [
      "-loglevel",
      "quiet",
      "-f",
      "concat",
      "-safe",
      "0",
      "-vn",
      "-i",
      "files.txt",
      "-progress",
      progress_file_path,
      "#{id}.mp4"
    ]

    {_output, 0} = System.cmd(command, args, cd: Media.out_path(media), parallelism: true)

    id
  end
end
