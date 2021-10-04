defmodule Ambry.Media.Processor.M4BConcat do
  @moduledoc """
  A media processor that concatenates a collection of M4B files and then
  converts them to dash streaming format.
  """

  import Ambry.Media.Processor.Shared

  def can_run?(media) do
    media |> files(".m4b") |> length() > 1
  end

  def run(media) do
    filename = concat_m4b!(media)
    create_mpd!(media, filename)
    finalize!(media, filename)
  end

  defp concat_m4b!(media) do
    file_list_txt_path = Path.join([media.source_path, "files.txt"])

    file_list_txt =
      media
      |> files(".m4b")
      |> Enum.sort()
      |> Enum.map_join("\n", &"file '#{&1}'")

    File.write!(file_list_txt_path, file_list_txt)

    filename = Ecto.UUID.generate()
    command = "ffmpeg"
    args = ["-f", "concat", "-safe", "0", "-i", "files.txt", "-acodec", "copy", "#{filename}.mp4"]

    {_output, 0} = System.cmd(command, args, cd: media.source_path, parallelism: true)

    filename
  end
end
