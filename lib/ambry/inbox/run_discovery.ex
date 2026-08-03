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

      {:error, reason} = error ->
        Logger.warning(fn -> "Inbox discovery failed: #{inspect(reason)}" end)
        error
    end
  end
end
