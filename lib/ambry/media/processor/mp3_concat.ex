defmodule Ambry.Media.Processor.MP3Concat do
  @moduledoc """
  A media processor that concatenates a collection of MP3 files and then
  converts them to dash streaming format.
  """

  import Ambry.Media.Processor.Shared

  @extensions ~w(.mp3)

  def can_run?(media) do
    media |> files(@extensions) |> length() > 1
  end

  def run(media) do
    filename = concat_mp3!(media)
    create_stream!(media, filename)
    finalize!(media, filename)
  end

  defp concat_mp3!(media) do
    file_list_txt_path = Path.join([media.source_path, "files.txt"])

    file_list_txt =
      media
      |> files(@extensions)
      |> Enum.map_join("\n", &"file '#{&1}'")

    File.write!(file_list_txt_path, file_list_txt)

    filename = Ecto.UUID.generate()
    command = "ffmpeg"
    args = ["-f", "concat", "-safe", "0", "-i", "files.txt", "#{filename}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: media.source_path, parallelism: true)

    filename
  end
end
