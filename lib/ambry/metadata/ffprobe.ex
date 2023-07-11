defmodule Ambry.Metadata.FFProbe do
  @moduledoc """
  Extract metadata from files using ffprobe
  """

  alias Ambry.Paths
  alias Ambry.Uploads.File

  require Logger

  def get_metadata(%File{} = file) do
    disk_path = Paths.web_to_disk(file.path)
    command = "ffprobe"

    args = [
      "-hide_banner",
      "-loglevel",
      "panic",
      "-show_format",
      "-show_streams",
      "-show_chapters",
      "-show_private_data",
      "-print_format",
      "json",
      disk_path
    ]

    Logger.debug(fn -> "[Ambry.Metadata.FFProbe] ffprobe " <> Enum.join(args, " ") end)

    case System.cmd(command, args, parallelism: true) do
      {output, 0} ->
        parse_output(output)

      {output, code} ->
        Logger.warn(fn ->
          "[Ambry.Metadata.FFProbe] ffprobe failed - code: #{code}, output: #{output}"
        end)

        {:error, :probe_failed}
    end
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, reason} ->
        Logger.warn(fn ->
          "[Ambry.Metadata.FFProbe] ffprobe failed - reason: #{inspect(reason)}"
        end)

        {:error, :probe_failed}
    end
  end
end
