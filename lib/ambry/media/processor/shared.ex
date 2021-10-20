defmodule Ambry.Media.Processor.Shared do
  @moduledoc """
  Shared functions for media processors.
  """

  import Ambry.Paths

  alias Ambry.Media

  def files(media, extensions) do
    media.source_path
    |> File.ls!()
    |> Enum.filter(&(Path.extname(&1) in extensions))
    |> NaturalSort.sort()
  end

  def create_mpd!(media, filename) do
    command = "shaka-packager"

    args = [
      "in=#{filename}.mp4,stream=audio,out=#{filename}.mp4",
      # "--dash_force_segment_list",
      "--base_urls",
      "/uploads/media/",
      "--mpd_output",
      "#{filename}.mpd"
    ]

    {_output, 0} = System.cmd(command, args, cd: media.source_path, parallelism: true)
  end

  def finalize!(media, filename) do
    media_folder = Path.join(uploads_path(), "media")
    mpd_dest = Path.join([media_folder, "#{filename}.mpd"])
    mp4_dest = Path.join([media_folder, "#{filename}.mp4"])

    File.mkdir_p!(media_folder)

    File.rename!(
      Path.join(media.source_path, "#{filename}.mpd"),
      mpd_dest
    )

    File.rename!(
      Path.join(media.source_path, "#{filename}.mp4"),
      mp4_dest
    )

    duration = get_duration(mp4_dest)

    Media.update_media(
      media,
      %{
        mpd_path: "/uploads/media/#{filename}.mpd",
        mp4_path: "/uploads/media/#{filename}.mp4",
        duration: duration,
        status: :ready
      },
      for: :processor_update
    )
  end

  defp get_duration(file) do
    command = "ffprobe"
    args = ["-i", file, "-show_entries", "format=duration", "-v", "quiet", "-of", "csv='p=0'"]
    {output, 0} = System.shell(Enum.join([command | args], " "))
    {duration, "\n"} = Decimal.parse(output)

    duration
  end
end
