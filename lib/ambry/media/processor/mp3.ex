defmodule Ambry.Media.Processor.MP3 do
  @moduledoc """
  A media processor that converts a single MP3 to dash & hls streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media
  alias Ambry.Media.Processor.ProgressTracker

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
    [mp3_file] = Media.files(media, @extensions, full?: true)

    id = Media.output_id(media)
    progress_file_path = "#{id}.progress"

    {:ok, _progress_tracker} = ProgressTracker.start(media, progress_file_path, @extensions)

    run_command!(
      "ffmpeg",
      [
        "-loglevel",
        "quiet",
        "-vn",
        "-i",
        "#{mp3_file}",
        "-progress",
        progress_file_path,
        "#{id}.mp4"
      ],
      cd: Media.out_path(media)
    )

    id
  end
end
