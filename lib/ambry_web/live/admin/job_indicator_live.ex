defmodule AmbryWeb.Admin.JobIndicatorLive do
  @moduledoc """
  The ambient background-work indicator in the admin header.

  The overview has a whole section about the queues; this is the glance
  version, because the moment an operator most wants to know whether the
  server is working is while they are somewhere else.

  **A nested LiveView, not a hook on the page.** An `on_mount` hook assigning
  onto the page's socket makes every update run the open page's `render/1`,
  and its message has to be swallowed by the hook so it does not crash the
  admin LiveViews that define no `handle_info/2`. With its own process the
  page is not involved at all.

  **Sticky**, so it is not torn down on live navigation and the spinner keeps
  spinning across a page change.

  **It watches; it does not poll.** `Ambry.Jobs.subscribe/0` puts this process
  on Oban's `:insert` channel and the republished job telemetry, debounced,
  because a queue draining forty items sends forty signals with one answer.
  The slow heartbeat that remains covers the two plugins that change the
  counts without announcing themselves.

  **It renders its quiet state**, because a widget that only appears when
  there is news is indistinguishable from a broken one. Failures get their own
  count: "busy" and "broken" are different answers, and only one is a reason
  to stop what you are doing.
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

  # Everything else on the subscription means "a job moved, go and look",
  # whether it is republished telemetry or Oban's raw insert notification.
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

  # One fact, most-active first: what the server is doing now beats what it is
  # about to do. The rest is in the tooltip; the header has a title to fit.
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
