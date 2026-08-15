defmodule Ambry.Jobs do
  @moduledoc """
  What the background queues are doing, in the terms the operator asks it in.

  Everything slow in Ambry happens in a job — probing files, asking the
  metadata providers, copying bytes into a library root, packaging, thumbnails
  — and until this existed the admin could not tell "still working" from
  "done" from "failed and you will never know". The per-record answer already
  existed (`Ambry.Inbox.Progress` puts a scrim on a busy row); this is the
  same question asked of the server as a whole.

  ## Deliberately not Oban Web

  Oban Web is mounted at `/admin/oban` and is better at every detail than
  anything reimplemented here. This exists to answer two questions without
  leaving the page — *is the server busy?* and *did something break?* — and to
  link through when the answer is yes. So it reports counts per queue and a
  short list of recent failures, and nothing else.

  ## Idle queues are still in the summary

  The summary lists every *configured* queue, including the ones holding
  nothing — a query that groups the job table alone cannot tell an idle queue
  from one that was deleted from the config, and the caller deserves to know
  which it is. Whether an idle row gets *rendered* is the caller's decision;
  the overview drops them and says "nothing running" in one line instead.

  ## "Recently" is the pruner's word, not ours

  The Oban pruner deletes finished jobs after a day, so a failure count is
  always "in about the last day" and there is no honest way to say more from
  this table. Anything that has to outlive that is written onto the record it
  concerns — an inbox item's `issue`, a recording's `missing_since` — and the
  overview reads those separately.

  ## Watching, rather than asking every few seconds

  `subscribe/0` puts a process on the two signals Oban already emits, so a
  display can react to a job moving instead of checking whether one has:

    * **`Oban.Notifier`, `:insert` channel** — Oban's own pub/sub, which on
      Postgres is `LISTEN/NOTIFY`. Fires when jobs are inserted, and also
      when the Stager promotes `scheduled` rows to `available`, so "queued"
      is live without anyone announcing it by hand at eight call sites.
    * **`[:oban, :job, :start | :stop | :exception]` telemetry** — the
      execution transitions. `attach_telemetry/0` hangs one global handler
      on these at boot and republishes them through `Ambry.PubSub`, so the
      cost is one broadcast per job rather than one telemetry handler per
      viewer, and a subscriber that crashes cannot take a handler down
      inside the process running somebody's import.

  **Between them they cover every transition a queue makes on its own.**
  What they do not cover is the housekeeping: `Oban.Plugins.Lifeline`
  rescuing a job orphaned by a dead node, and `Oban.Plugins.Pruner` deleting
  a discarded one a day later. Neither announces itself, so a display should
  still hold a slow heartbeat — but slow, minutes rather than seconds,
  because those are the only two things it is covering for.
  """

  use Boundary, deps: [Ambry, Ambry.PubSub]

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
  Republishes Oban's job telemetry through `Ambry.PubSub`. Called once at boot.

  Idempotent: `:telemetry` refuses a duplicate handler id, and a second call
  in the same VM (a test, a release upgrade) is a no-op rather than an error.
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

  The caller will receive `%Ambry.Jobs.PubSub.JobActivity{}` structs and
  Oban's own `{:notification, :insert, payload}` messages. Both mean the same
  thing — go and look again — so a caller is free to treat them alike, and
  should debounce: a queue draining forty items emits forty of these.
  """
  def subscribe do
    :ok = PubSub.subscribe(JobActivity.topic())
    :ok = Oban.Notifier.listen([:insert])
  end

  @doc """
  Per-queue counts, plus the totals.

  Four numbers per queue, because they mean four different things to somebody
  deciding whether to wait:

    * `running` — executing right now
    * `queued` — available or scheduled, so it will run without help
    * `retrying` — failed and will try again on its own (the metadata queue
      lives here whenever a provider is rate-limiting)
    * `failed` — discarded or cancelled; it will not try again

  Only `failed` is a call to action. The rest are the server working.
  """
  def summary do
    counted = counts_by_queue()

    queues =
      Enum.map(configured_queues(), fn queue ->
        counted |> Map.get(queue, empty_counts()) |> Map.put(:queue, queue)
      end)

    # A queue that was removed from the config but still holds rows would
    # otherwise vanish from a display whose whole job is "is anything left
    # running", so unknown queues are appended rather than dropped.
    stragglers =
      counted
      |> Map.drop(configured_queues())
      |> Enum.map(fn {queue, counts} -> Map.put(counts, :queue, queue) end)

    all = queues ++ Enum.sort_by(stragglers, & &1.queue)

    Map.put(totals(all), :queues, all)
  end

  @doc """
  The most recent jobs that gave up, newest first.

  A count says something broke; this says what, which is the difference
  between a widget the operator reads and one they learn to ignore. The error
  is the last line of Oban's formatted exception, which is the part that names
  the failure rather than the stack that led to it.
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

  `retrying` counts as busy: a job mid-backoff is going to run again and
  change something underneath whoever is looking, which is the only reason
  this question gets asked.
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

  # Read from the config rather than from Oban's running state: this is asked
  # by a LiveView on every refresh, and it is a question about how the server
  # is set up, not about what the supervisor is doing this millisecond.
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
