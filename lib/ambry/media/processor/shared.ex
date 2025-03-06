defmodule Ambry.Media.Processor.Shared do
  @moduledoc """
  Shared functions for media processors.
  """

  import Ambry.Paths

  alias Ambry.Media, as: MediaContext
  alias Ambry.Media.Media
  alias Ambry.Media.Processor.ProgressTracker

  require Logger

  def filter_filenames(filenames, extensions) do
    filenames
    |> Enum.filter(&(Path.extname(&1) in extensions))
    |> Enum.sort(NaturalOrder)
  end

  def create_concat_text_file!(media, extensions) do
    file_list_txt_path = Media.out_path(media, "files.txt")

    file_list_txt =
      media
      |> Media.files(extensions)
      |> Enum.map_join("\n", fn filename ->
        "file #{quote_and_escape_filename(filename)}"
      end)

    File.write!(file_list_txt_path, file_list_txt)
  end

  # This quotes and escapes filenames according to what ffmpeg requires. See the
  # docs here: https://www.ffmpeg.org/ffmpeg-utils.html#Quoting-and-escaping
  defp quote_and_escape_filename(filename) do
    filename
    |> String.split("'")
    |> Enum.map_join("\\'", &"'#{&1}'")
  end

  def concat_files!(media, extensions) do
    create_concat_text_file!(media, extensions)

    id = Media.output_id(media)
    progress_file_path = "#{id}.progress"

    {:ok, progress_tracker} = ProgressTracker.start(media, progress_file_path, extensions)

    try do
      run_command!(
        "ffmpeg",
        [
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
        ],
        cd: Media.out_path(media)
      )

      id
    after
      ProgressTracker.stop(progress_tracker)
    end
  end

  def create_stream!(media, id) do
    dir = Media.out_path(media)
    mpd_file = Media.out_path(media, "#{id}.mpd")
    hls_file = Media.out_path(media, "#{id}.m3u8")

    run_command!(
      "shaka-packager",
      [
        "in=#{id}.mp4,stream=audio,out=#{id}.mp4,playlist_name=#{id}_0.m3u8",
        "--base_urls",
        "/uploads/media/",
        "--hls_base_url",
        "/uploads/media/",
        "--mpd_output",
        "#{mpd_file}",
        "--hls_master_playlist_output",
        "#{hls_file}",
        "-quiet"
      ],
      cd: dir
    )
  end

  def finalize!(media, id) do
    mpd_dest = media_disk_path("#{id}.mpd")
    hls_playlist_dest = media_disk_path("#{id}_0.m3u8")
    hls_master_dest = media_disk_path("#{id}.m3u8")
    mp4_dest = media_disk_path("#{id}.mp4")

    File.rename!(Media.out_path(media, "#{id}.mpd"), mpd_dest)
    File.rename!(Media.out_path(media, "#{id}_0.m3u8"), hls_playlist_dest)
    File.rename!(Media.out_path(media, "#{id}.m3u8"), hls_master_dest)
    File.rename!(Media.out_path(media, "#{id}.mp4"), mp4_dest)

    duration = get_inaccurate_duration(mp4_dest)

    MediaContext.update_media(
      media,
      %{
        mpd_path: "/uploads/media/#{id}.mpd",
        hls_path: "/uploads/media/#{id}.m3u8",
        mp4_path: "/uploads/media/#{id}.mp4",
        duration: duration,
        status: :ready
      }
    )
  end

  def get_inaccurate_duration(file) do
    # getting the duration from the metadata is safe for the MP4 files we
    # produce. But to get duration from unknown source files, we should not rely
    # on the metadata reported duration.

    output =
      run_command!("ffprobe", [
        "-i",
        file,
        "-print_format",
        "json",
        "-show_entries",
        "format=duration",
        "-v",
        "quiet"
      ])

    %{"format" => %{"duration" => duration_string}} = Jason.decode!(output)

    Decimal.new(duration_string)
  end

  def run_command!(command, args, opts \\ []) do
    Logger.info(fn -> "Running `#{command} #{Enum.join(args, " ")}`" end)
    {output, 0} = System.cmd(command, args, Keyword.put(opts, :parallelism, true))
    output
  end
end
