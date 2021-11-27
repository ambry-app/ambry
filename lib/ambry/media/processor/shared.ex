defmodule Ambry.Media.Processor.Shared do
  @moduledoc """
  Shared functions for media processors.
  """

  import Ambry.Paths

  alias Ambry.Media

  def get_id(media) do
    %{
      mp4_path: mp4_path,
      mpd_path: mpd_path,
      hls_path: hls_path
    } = media

    with [path | _] when is_binary(path) <- Enum.filter([mp4_path, mpd_path, hls_path], & &1),
         {:ok, id} <- path |> Path.basename() |> Path.rootname() |> Ecto.UUID.cast() do
      id
    else
      _anything ->
        Ecto.UUID.generate()
    end
  end

  def files(media, extensions) do
    media.source_path
    |> File.ls!()
    |> filter_filenames(extensions)
  end

  def filter_filenames(filenames, extensions) do
    filenames
    |> Enum.filter(&(Path.extname(&1) in extensions))
    |> NaturalSort.sort()
  end

  def create_concat_text_file!(media, extensions) do
    file_list_txt_path = out_path(media, "files.txt")

    file_list_txt =
      media
      |> files(extensions)
      |> Enum.map_join("\n", fn filename ->
        "file #{quote_and_escape_filename("../#{filename}")}"
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

  def create_stream!(media, id) do
    command = "shaka-packager"

    args = [
      "in=#{id}.mp4,stream=audio,out=#{id}.mp4,playlist_name=#{id}_0.m3u8",
      "--base_urls",
      "/uploads/media/",
      "--hls_base_url",
      "/uploads/media/",
      "--mpd_output",
      "#{id}.mpd",
      "--hls_master_playlist_output",
      "#{id}.m3u8"
    ]

    {_output, 0} = System.cmd(command, args, cd: out_path(media), parallelism: true)
  end

  def finalize!(media, id) do
    media_folder = Path.join(uploads_folder_disk_path(), "media")
    mpd_dest = Path.join([media_folder, "#{id}.mpd"])
    hls_playlist_dest = Path.join([media_folder, "#{id}_0.m3u8"])
    hls_master_dest = Path.join([media_folder, "#{id}.m3u8"])
    mp4_dest = Path.join([media_folder, "#{id}.mp4"])

    File.mkdir_p!(media_folder)
    File.rename!(out_path(media, "#{id}.mpd"), mpd_dest)
    File.rename!(out_path(media, "#{id}_0.m3u8"), hls_playlist_dest)
    File.rename!(out_path(media, "#{id}.m3u8"), hls_master_dest)
    File.rename!(out_path(media, "#{id}.mp4"), mp4_dest)

    duration = get_duration(mp4_dest)

    Media.update_media(
      media,
      %{
        mpd_path: "/uploads/media/#{id}.mpd",
        hls_path: "/uploads/media/#{id}.m3u8",
        mp4_path: "/uploads/media/#{id}.mp4",
        duration: duration,
        status: :ready
      },
      for: :processor_update
    )
  end

  defp get_duration(file) do
    # getting the duration from the metadata is safe for the MP4 files we
    # produce. But to get duration from unknown source files, we should not rely
    # on the metadata reported duration.

    command = "ffprobe"

    args = [
      "-i",
      file,
      "-print_format",
      "json",
      "-show_entries",
      "format=duration",
      "-v",
      "quiet"
    ]

    {output, 0} = System.cmd(command, args, parallelism: true)
    %{"format" => %{"duration" => duration_string}} = Jason.decode!(output)

    Decimal.new(duration_string)
  end

  def out_path(media, file \\ "") do
    Path.join([media.source_path, "_out", file])
  end

  def source_path(media, file \\ "") do
    Path.join([media.source_path, file])
  end
end
