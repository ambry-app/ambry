defmodule Ambry.Search.RunDrain do
  @moduledoc """
  The backstop under `Ambry.Search.Listener`.

  `NOTIFY` is fire-and-forget, so a notification raised while the listener was
  down is lost while the queue row it referred to is not. This sweeps up what
  that leaves. In a healthy server it finds nothing, every time — a run that
  keeps finding work is the signal that the listener isn't listening.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Ambry.Search.Drain

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, count} = Drain.run()

    if count > 0 do
      Logger.warning(fn ->
        "Search index: the cron backstop drained #{count} references the listener missed"
      end)
    end

    {:ok, count}
  end
end
