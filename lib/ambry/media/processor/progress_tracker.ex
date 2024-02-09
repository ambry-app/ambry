defmodule Ambry.Media.Processor.ProgressTracker do
  @moduledoc """
  Tracks the progress of an ffmpeg command by tailing the progress file it
  generates. Publishes periodic progress events using `Ambry.PubSub`.
  """

  use GenServer

  import Ambry.Media.Processor.Shared, only: [get_inaccurate_duration: 1]

  alias Ambry.Media.Media
  alias Ambry.PubSub

  # Client

  def start(media, file, extensions) do
    file_path = Media.out_path(media, file)
    File.touch!(file_path)

    GenServer.start(__MODULE__, %{media: media, file_path: file_path, extensions: extensions})
  end

  # Server (callbacks)

  @impl GenServer
  def init(state) do
    full_duration =
      state.media
      |> Media.files(state.extensions, full?: true)
      |> Task.async_stream(&get_inaccurate_duration/1, ordered: false)
      |> Stream.map(fn {:ok, duration} -> duration end)
      |> Enum.reduce(&Decimal.add/2)

    port = Port.open({:spawn, "tail -f #{state.file_path}"}, [:binary])

    {:ok, Map.merge(state, %{port: port, duration: full_duration})}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    progress =
      data
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(fn kvp ->
        kvp |> String.split("=") |> Enum.map(&String.trim/1) |> List.to_tuple()
      end)

    current_time = get_current_time(progress)
    action = get_action(progress)

    publish_progress(state.media, state.duration, current_time)

    case action do
      :continue ->
        {:noreply, state}

      :end ->
        Port.close(port)
        {:stop, :normal, state}
    end
  end

  defp publish_progress(media, duration, current_time) do
    progress = Decimal.div(current_time, duration)
    PubSub.broadcast_progress(media, progress)
  end

  defp get_current_time(progress),
    do:
      Enum.find_value(progress, fn
        {"out_time", "N/A"} -> false
        {"out_time", out_time} -> timestamp_to_seconds(out_time)
        _else -> false
      end)

  @timestamp_regex ~r/([0-9]{2}):([0-9]{2}):([0-9]{2}(?:\.[0-9]+)?)/
  defp timestamp_to_seconds(timestamp) do
    [_, hours, minutes, seconds] = Regex.run(@timestamp_regex, timestamp)

    seconds
    |> Decimal.new()
    |> Decimal.add(minutes |> Decimal.new() |> Decimal.mult(60))
    |> Decimal.add(hours |> Decimal.new() |> Decimal.mult(3600))
  end

  defp get_action(progress),
    do:
      Enum.find_value(progress, fn
        {"progress", "continue"} -> :continue
        {"progress", "end"} -> :end
        _else -> false
      end)
end
