defmodule Ambry.Media.Scanner.Probe do
  @moduledoc """
  Reads what an audio file actually *is*: container, codec, size, duration,
  and any embedded chapter markers.

  This is the direct-play replacement for transcoding: nothing is decoded,
  repackaged, or written — the file is measured and left alone.

  ## Durations

  `Ambry.Media.Processor.Shared.get_inaccurate_duration/1` trusts whatever the
  container claims, which is only safe for the MP4s that pipeline produced
  itself. Source files are not so cooperative: a VBR mp3 with no Xing/VBRI
  header has no duration to report, so ffprobe extrapolates one from the first
  frame's bitrate and can be minutes wrong over a long book.

  So the container's word is taken only for formats that genuinely know
  (MP4/M4B sample tables, FLAC's STREAMINFO, Ogg granule positions, WAV's
  fixed byte rate, Matroska's header). Everything else is decode-counted once,
  here at scan time, and the gap between the claimed and the real duration is
  the tell for seek accuracy: a container that guessed the length wrong has no
  index to seek by either, which is exactly the VBR-mp3-without-Xing case.
  """

  alias Ambry.Media.Chapters.Utils

  require Logger

  @enforce_keys [:path, :size, :duration, :seek_accuracy]
  defstruct [
    :path,
    :size,
    :format,
    :codec,
    :mime,
    :duration,
    :seek_accuracy,
    chapters: []
  ]

  # containers whose reported duration is derived from real indexing data
  @indexed_formats ~w(mov,mp4,m4a,3gp,3g2,mj2 flac ogg wav matroska,webm)

  @mime_types %{
    ".aac" => "audio/aac",
    ".flac" => "audio/flac",
    ".m4a" => "audio/mp4",
    ".m4b" => "audio/mp4",
    ".mp3" => "audio/mpeg",
    ".mp4" => "audio/mp4",
    ".oga" => "audio/ogg",
    ".ogg" => "audio/ogg",
    ".opus" => "audio/ogg",
    ".wav" => "audio/wav"
  }

  # a duration this far off the real one means the container was guessing
  @tolerance_seconds Decimal.new("1")
  @tolerance_fraction Decimal.new("0.005")

  @doc """
  Probes a single audio file.

  Returns `{:ok, %Probe{}}`, or `{:error, reason}` if the file can't be read
  or carries no audio stream we can measure.
  """
  def run(path) do
    with {:ok, %File.Stat{size: size}} <- File.stat(path),
         {:ok, json} <- ffprobe(path),
         {:ok, data} <- decode(json) do
      build(path, size, data)
    end
  end

  defp build(path, size, data) do
    format = data["format"] || %{}

    case duration(path, format) do
      nil ->
        {:error, :no_duration}

      {duration, seek_accuracy} ->
        {:ok,
         %__MODULE__{
           path: path,
           size: size,
           format: format["format_name"],
           codec: audio_codec(data),
           mime: mime_type(path),
           duration: duration,
           seek_accuracy: seek_accuracy,
           chapters: chapters(data)
         }}
    end
  end

  defp duration(path, format) do
    claimed = decimal(format["duration"])

    if format["format_name"] in @indexed_formats do
      claimed && {claimed, :exact}
    else
      decode_counted(path, claimed)
    end
  end

  defp decode_counted(path, claimed) do
    case decoded_duration(path) do
      {:ok, decoded} -> {decoded, seek_accuracy(claimed, decoded)}
      :error -> claimed && {claimed, :approximate}
    end
  end

  # A container that got the length right was reading an index; one that
  # guessed can't seek accurately either.
  defp seek_accuracy(nil, _decoded), do: :approximate

  defp seek_accuracy(claimed, decoded) do
    tolerance = Decimal.max(@tolerance_seconds, Decimal.mult(decoded, @tolerance_fraction))

    if claimed |> Decimal.sub(decoded) |> Decimal.abs() |> Decimal.compare(tolerance) == :gt do
      :approximate
    else
      :exact
    end
  end

  defp audio_codec(data) do
    data
    |> Map.get("streams", [])
    |> Enum.find(%{}, &(&1["codec_type"] == "audio"))
    |> Map.get("codec_name")
  end

  defp mime_type(path) do
    Map.get(@mime_types, path |> Path.extname() |> String.downcase())
  end

  defp chapters(data) do
    case Utils.adapt_ffmpeg_chapters(data) do
      {:ok, chapters} -> chapters
      {:error, _reason} -> []
    end
  end

  defp ffprobe(path) do
    run_command("ffprobe", [
      "-i",
      path,
      "-print_format",
      "json",
      "-show_format",
      "-show_streams",
      "-show_chapters",
      "-v",
      "quiet"
    ])
  end

  # Decodes the whole file without writing anything, asking ffmpeg to report
  # its progress in microseconds; the last report is the real duration.
  defp decoded_duration(path) do
    case run_command("ffmpeg", [
           "-i",
           path,
           "-vn",
           "-v",
           "quiet",
           "-f",
           "null",
           "-progress",
           "pipe:1",
           "-"
         ]) do
      {:ok, output} -> parse_progress_duration(output)
      {:error, _reason} -> :error
    end
  end

  defp parse_progress_duration(output) do
    case Regex.scan(~r/^out_time_us=(\d+)$/m, output) do
      [] ->
        Logger.warning(fn -> "No duration reported while decoding" end)
        :error

      matches ->
        [_match, microseconds] = List.last(matches)

        {:ok, microseconds |> Decimal.new() |> Decimal.div(1_000_000) |> Decimal.round(6)}
    end
  end

  defp run_command(command, args) do
    Logger.info(fn -> "Running `#{command} #{Enum.join(args, " ")}`" end)

    case System.cmd(command, args, parallelism: true, stderr_to_stdout: false) do
      {output, 0} ->
        {:ok, output}

      {output, code} ->
        Logger.warning(fn -> "#{command} failed. Code: #{code}, Output: #{output}" end)
        {:error, :probe_failed}
    end
  rescue
    error in ErlangError ->
      Logger.warning(fn -> "Couldn't run #{command}: #{inspect(error)}" end)
      {:error, :probe_failed}
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, data} ->
        {:ok, data}

      {:error, error} ->
        Logger.warning(fn -> "ffprobe json decode failed: #{inspect(error)}" end)
        {:error, :invalid_json}
    end
  end

  defp decimal(nil), do: nil

  defp decimal(string) do
    case Decimal.parse(string) do
      {decimal, ""} -> if Decimal.positive?(decimal), do: decimal
      _unparseable -> nil
    end
  end
end
