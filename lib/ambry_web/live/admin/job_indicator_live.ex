defmodule AmbryWeb.Admin.JobIndicatorLive do
  @moduledoc """
  The ambient background-work indicator in the admin header.

  The overview has a whole section about the queues; this is the glance
  version, and it exists because the moment an operator most wants to know
  whether the server is working is while they are somewhere else — mid-form,
  having just pressed Import.

  ## Why this is a LiveView and not a hook on the page

  The first version lived in an `on_mount` hook and assigned onto *the
  page's* socket, so every update ran the open page's `render/1` — cheap,
  because change tracking skips the parts whose assigns did not move, but
  the page owned work it had no reason to do, and the update message had to
  be swallowed by the hook so it didn't crash the many admin LiveViews that
  define no `handle_info/2`.

  A nested LiveView has its own process and its own diff. The page it sits
  in is not involved: it does not re-render, it does not need the data
  threaded through `layout/1`, and nothing has to be careful about a stray
  message.

  ## Sticky

  Rendered with `sticky: true`, so it is not torn down and rebuilt on every
  live navigation. That keeps the spinner spinning across a page change
  rather than blinking through mount → idle → busy each time.

  ## It watches; it does not poll

  `Ambry.Jobs.subscribe/0` puts this process on Oban's `:insert` notifier
  channel (Postgres `LISTEN/NOTIFY`) and on the republished
  `[:oban, :job, :start | :stop | :exception]` telemetry, so the display
  moves when a job does rather than up to a tick later.

  Signals are **debounced**, because a queue draining forty items sends
  forty of them and the answer to all forty is one query.

  The heartbeat that remains is slow and covers exactly two things that
  change the counts without announcing themselves: `Oban.Plugins.Lifeline`
  rescuing a job orphaned by a dead node, and `Oban.Plugins.Pruner` dropping
  a discarded one a day later. Neither is urgent, so neither justifies a
  fast clock.

  ## It renders its quiet state

  A widget that only appears when there is news is indistinguishable from a
  broken one, so a quiet server gets a dim dot and the word Idle. That is
  also what makes the spinner mean something when it does show up. Failures
  get their own count beside it, because "busy" and "broken" are different
  answers and only one of them is a reason to stop what you are doing.
  """

  use AmbryWeb, :nested_live_view

  alias Ambry.Jobs

  # Long enough to collapse a burst into one query, short enough that a
  # single job starting still feels immediate.
  @debounce 250

  # The backstop, for the two housekeeping plugins that change the counts
  # silently. Minutes, not seconds — see the moduledoc.
  @heartbeat to_timeout(minute: 2)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Jobs.subscribe()
      Process.send_after(self(), :heartbeat, @heartbeat)
    end

    {:ok, socket |> assign(reload_queued: false) |> load(), layout: false}
  end

  @impl Phoenix.LiveView
  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(reload_queued: false) |> load()}
  end

  def handle_info(:heartbeat, socket) do
    Process.send_after(self(), :heartbeat, @heartbeat)

    {:noreply, load(socket)}
  end

  # Everything else on the subscription means the same thing — a job moved,
  # go and look — whether it arrived as our own republished telemetry or as
  # Oban's raw insert notification.
  def handle_info(_signal, socket), do: {:noreply, nudge(socket)}

  defp load(socket), do: assign(socket, jobs: Jobs.summary())

  # Coalesce. Forty jobs finishing is one question, asked once.
  defp nudge(%{assigns: %{reload_queued: true}} = socket), do: socket

  defp nudge(socket) do
    Process.send_after(self(), :reload, @debounce)

    assign(socket, reload_queued: true)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.link
      href={~p"/admin/oban"}
      target="_blank"
      rel="noopener"
      title={detail(@jobs)}
      class="bg-white/5 flex flex-none items-center gap-2 rounded-md px-2 py-1 hover:bg-white/10"
      data-role="job-indicator"
    >
      <.icon :if={Jobs.busy?(@jobs)} name="fa-rotate" class="h-3.5 w-3.5 animate-spin text-zinc-300" />
      <span :if={!Jobs.busy?(@jobs)} class="h-2 w-2 rounded-full bg-zinc-600" />
      <span class="hidden text-xs text-zinc-300 sm:inline">{words(@jobs)}</span>
      <span
        :if={@jobs.failed > 0}
        class="bg-red-400/15 rounded-sm px-1 text-xs font-bold tabular-nums text-red-300"
        data-role="job-indicator-failed"
      >
        {@jobs.failed}
      </span>
    </.link>
    """
  end

  # One fact, most-active first: what the server is doing right now beats what
  # it is about to do. The rest is in the tooltip rather than the header,
  # which has a page title to leave room for.
  defp words(%{running: n}) when n > 0, do: "#{n} running"
  defp words(%{queued: n}) when n > 0, do: "#{n} queued"
  defp words(%{retrying: n}) when n > 0, do: "#{n} retrying"
  defp words(_idle), do: "Idle"

  defp detail(jobs) do
    [
      "#{jobs.running} running",
      "#{jobs.queued} queued",
      "#{jobs.retrying} waiting to retry",
      "#{jobs.failed} failed recently"
    ]
    |> Enum.join(", ")
    |> Kernel.<>(". Opens the Oban dashboard.")
  end
end
