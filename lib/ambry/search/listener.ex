defmodule Ambry.Search.Listener do
  @moduledoc """
  Drains the search queue the moment a write commits.

  The enqueue trigger ends with `pg_notify('search_index_queue', '')`, and
  Postgres delivers only when the transaction that raised it commits, never on
  rollback and never before the queue rows are visible. So this needs no
  coordination with the writer and there is no call site to forget.

  Identical notifications inside one transaction collapse into a single
  delivery, so a 300-item import wakes this once.

  **Failure is a slower index, not a wrong one.** `NOTIFY` is fire-and-forget,
  so one raised while this process restarts is gone. The durable part is the
  queue row, which is why `Ambry.Search.RunDrain` also runs on a cron: this is
  an optimization over that backstop.

  """

  use GenServer

  alias Ambry.Repo
  alias Ambry.Search.Drain

  require Logger

  @channel "search_index_queue"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{}, {:continue, :listen}}
  end

  @impl GenServer
  def handle_continue(:listen, state) do
    {:ok, pid} = Postgrex.Notifications.start_link(Repo.config())
    {:ok, _ref} = Postgrex.Notifications.listen(pid, @channel)

    # Anything enqueued while nobody was listening (a restart, a deploy) is
    # drained now rather than waiting for the next write or the cron.
    drain()

    {:noreply, Map.put(state, :notifications, pid)}
  end

  @impl GenServer
  def handle_info({:notification, _pid, _ref, @channel, _payload}, state) do
    drain()

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp drain do
    {:ok, _count} = Drain.run()
  rescue
    error ->
      # A drain that raises has already rolled its batch back onto the queue,
      # so the cron picks it up. Staying alive matters more than this pass.
      Logger.error(fn -> "Search index drain failed: #{Exception.message(error)}" end)
  end
end
