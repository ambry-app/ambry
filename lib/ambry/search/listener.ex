defmodule Ambry.Search.Listener do
  @moduledoc """
  Drains the search queue the moment a write commits.

  The enqueue trigger ends with `pg_notify('search_index_queue', '')`, and
  Postgres delivers a notification only when the transaction that raised it
  commits — never on rollback, and never before the queue rows it refers to
  are visible. So this needs no coordination with the writer, and there is no
  call site anywhere to forget: promptness is structural in the same way
  correctness is.

  Identical notifications raised inside one transaction collapse into a single
  delivery, so a 300-item inbox import wakes this once, not three hundred
  times.

  ## Failure is a slower index, not a wrong one

  `NOTIFY` is fire-and-forget: a notification raised while this process is
  restarting is simply gone. The durable part is the queue row, which is why
  `Ambry.Search.RunDrain` also runs on a cron. This process is an optimization
  over that backstop — if it dies, the index is a minute behind instead of a
  moment.
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

    # Anything enqueued while nobody was listening — a restart, a deploy, the
    # initial migration's backfill — is drained now rather than waiting for
    # the next write or the cron.
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
      # so the cron backstop will pick it up. Staying alive matters more than
      # this pass did.
      Logger.error(fn -> "Search index drain failed: #{Exception.message(error)}" end)
  end
end
