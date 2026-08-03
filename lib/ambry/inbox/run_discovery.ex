defmodule Ambry.Inbox.RunDiscovery do
  @moduledoc """
  Scans the watched location for new inbox candidates.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 1

  alias Ambry.Inbox

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Inbox.discover() do
      {:ok, counts} = success ->
        Logger.info(fn -> "Inbox discovery: #{inspect(counts)}" end)
        success

      # Not a failure, and the only error `discover/0` can return: a location
      # it couldn't read is counted as `unreachable` rather than failing the
      # run. This runs hourly on a schedule, and an install that hasn't
      # registered any locations yet would otherwise produce a warning and a
      # discarded job every hour forever.
      {:error, :no_watched_locations} ->
        :ok
    end
  end
end
