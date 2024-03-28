defmodule Ambry.Media.Processor.MP4Copy do
  @moduledoc """
  A media processor that copies a single MP4 and converts it to dash & hls
  streaming format.
  """

  import Ambry.Media.Processor.Shared

  alias Ambry.Media.Media
  alias Ambry.Media.Processor.ProgressTracker

  @extensions ~w(.mp4 .m4a .m4b)

  def name do
    "Single MP4 Copy"
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
    id = convert_mp4!(media)
    create_stream!(media, id)
    finalize!(media, id)
  end

  defp convert_mp4!(media) do
    [mp4_file] = Media.files(media, @extensions, full?: true)

    id = Media.output_id(media)
    progress_file_path = "#{id}.progress"

    {:ok, _progress_tracker} = ProgressTracker.start(media, progress_file_path, @extensions)

    run_command!(
      "ffmpeg",
      [
        "-vn",
        "-i",
        "#{mp4_file}",
        "-c",
        "copy",
        "-progress",
        progress_file_path,
        "#{id}.mp4"
      ],
      cd: Media.out_path(media)
    )

    id
  end
end
