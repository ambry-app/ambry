defmodule Ambry.Jobs do
  @moduledoc """
  What the background queues are doing, in the terms the operator asks it in.

  Everything slow in Ambry happens in a job, and this answers two questions
  without leaving the page: *is the server busy?* and *did something break?*
  Anything more detailed is Oban Web's, mounted at `/admin/oban`.

  **Idle queues are still in the summary.** A query grouping the job table
  alone cannot tell an idle queue from one deleted from the config. Whether an
  idle row is *rendered* is the caller's decision.

  **"Recently" is the pruner's word.** Oban deletes finished jobs after a day,
  so a failure count is always "in about the last day". Anything that has to
  outlive that is written onto the record it concerns.

  ## Watching, rather than polling

  `subscribe/0` puts a process on the two signals Oban already emits:

    * **`Oban.Notifier`, `:insert` channel** — fires on insert, and when the
      Stager promotes `scheduled` rows to `available`, so "queued" is live.
    * **`[:oban, :job, :start | :stop | :exception]` telemetry**, republished
      through `Ambry.PubSub` by one global handler attached at boot, so the
      cost is one broadcast per job rather than a handler per viewer.

  Between them they cover every transition a queue makes on its own. They do
  not cover the housekeeping plugins (Lifeline rescuing an orphaned job,
  Pruner deleting a discarded one), so a display should still hold a
  heartbeat, in minutes rather than seconds.
  """

  use Boundary, deps: [Ambry, Ambry.PubSub], exports: [PubSub.JobActivity]

  import Ecto.Query

  alias Ambry.Jobs.PubSub.JobActivity
  alias Ambry.PubSub
  alias Ambry.Repo

  @telemetry_events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  @doc """
  Republishes Oban's job telemetry through `Ambry.PubSub`. Called once at
  boot, and idempotent: `:telemetry` refuses a duplicate handler id.
  """
  def attach_telemetry do
    case :telemetry.attach_many(
           "ambry-job-activity",
           @telemetry_events,
           &__MODULE__.handle_telemetry/4,
           :no_config
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  # Runs inside the process executing the job, so it does exactly one thing.
  def handle_telemetry([:oban, :job, event], _measurements, %{job: job}, _config) do
    event |> JobActivity.new(job.queue) |> PubSub.broadcast()

    :ok
  end

  def handle_telemetry(_event, _measurements, _metadata, _config), do: :ok

  @doc """
  Watch for anything that would change what `summary/0` returns.

  Delivers `%Ambry.Jobs.PubSub.JobActivity{}` structs and Oban's own
  `{:notification, :insert, payload}` messages. Both mean "go and look
  again", so debounce: a queue draining forty items emits forty of them.
  """
  def subscribe do
    :ok = PubSub.subscribe(JobActivity.topic())
    :ok = Oban.Notifier.listen([:insert])
  end

  @doc """
  Per-queue counts, plus the totals.

    * `running` — executing right now
    * `queued` — available or scheduled, so it will run without help
    * `retrying` — failed and will try again on its own
    * `failed` — discarded or cancelled; it will not try again

  Only `failed` is a call to action. The rest are the server working.
  """
  def summary do
    counted = counts_by_queue()

    queues =
      Enum.map(configured_queues(), fn queue ->
        counted |> Map.get(queue, empty_counts()) |> Map.put(:queue, queue)
      end)

    # Unknown queues are appended rather than dropped: one removed from the
    # config while still holding rows would otherwise vanish.
    stragglers =
      counted
      |> Map.drop(configured_queues())
      |> Enum.map(fn {queue, counts} -> Map.put(counts, :queue, queue) end)

    all = queues ++ Enum.sort_by(stragglers, & &1.queue)

    Map.put(totals(all), :queues, all)
  end

  @doc """
  The most recent jobs that gave up, newest first.

  A count says something broke; this says what. The error is the last line of
  Oban's formatted exception, which names the failure rather than the stack.
  """
  def recent_failures(limit \\ 5) do
    from(j in "oban_jobs",
      where: j.state in ~w(discarded cancelled),
      order_by: [desc: coalesce(j.discarded_at, j.cancelled_at)],
      limit: ^limit,
      select: %{
        id: j.id,
        queue: j.queue,
        worker: j.worker,
        state: j.state,
        at: coalesce(j.discarded_at, j.cancelled_at),
        errors: j.errors
      }
    )
    |> Repo.all()
    |> Enum.map(fn job ->
      job
      |> Map.put(:error, last_error(job.errors))
      |> Map.delete(:errors)
    end)
  end

  @doc """
  Whether anything at all is in flight.

  `retrying` counts as busy: a job mid-backoff will run again and change
  something underneath whoever is looking.
  """
  def busy?(%{running: running, queued: queued, retrying: retrying}),
    do: running + queued + retrying > 0

  defp counts_by_queue do
    from(j in "oban_jobs",
      where: j.state in ~w(executing available scheduled retryable discarded cancelled),
      group_by: j.queue,
      select:
        {j.queue,
         %{
           running: filter(count(j.id), j.state == "executing"),
           queued: filter(count(j.id), j.state in ~w(available scheduled)),
           retrying: filter(count(j.id), j.state == "retryable"),
           failed: filter(count(j.id), j.state in ~w(discarded cancelled))
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp totals(queues) do
    Enum.reduce(queues, empty_counts(), fn queue, totals ->
      Map.new(totals, fn {key, total} -> {key, total + Map.fetch!(queue, key)} end)
    end)
  end

  defp empty_counts, do: %{running: 0, queued: 0, retrying: 0, failed: 0}

  # From the config rather than Oban's running state: a question about how the
  # server is set up, asked on every LiveView refresh.
  defp configured_queues do
    :ambry
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Enum.map(fn {queue, _limit} -> to_string(queue) end)
    |> Enum.sort()
  end

  defp last_error([_ | _] = errors) do
    errors
    |> List.last()
    |> Map.get("error", "")
    |> String.split("\n", trim: true)
    |> List.first()
  end

  defp last_error(_none), do: nil
end
