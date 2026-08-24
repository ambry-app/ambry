defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  The admin landing page: what needs the operator, and whether the server is
  all right.

  Not a set of counts. A tile has to pass one test: **it can be in a bad
  state, and clicking it lands where you would fix it.** The inventory counts
  survive at the bottom as one quiet strip, because knowing the library's
  size is worth a glance even though it is never a task.

  The inbox is the daily loop, but a work queue over discovered files cannot
  answer *did something break while I wasn't looking* — failed jobs, an
  unmounted source, a rate-limiting provider, recordings whose files have
  gone missing are none of them inbox rows. The one click landing there would
  save is bought by the pending badge on the nav item instead.

  Four sections, ordered by who is waiting on whom. **Needs you** is work
  that will not move without a human. **Background work** is the server's
  turn, because "still working", "done" and "failed and you'll never know"
  otherwise look identical from here. **Problems** is what is wrong.
  **Library** is the inventory strip.

  Zero means different things in different sections: a queue with nothing in
  it is reported, because that *is* the answer to "is the server busy", while
  a problem with a count of zero is not, because a card of green zeroes
  teaches the eye to skip it.
  """

  use AmbryWeb, :admin_live_view

  alias Ambry.Accounts
  alias Ambry.Books
  alias Ambry.Inbox
  alias Ambry.Jobs
  alias Ambry.Jobs.PubSub.JobActivity
  alias Ambry.Library
  alias Ambry.Media
  alias Ambry.People
  alias Ambry.Wanted

  # Signals arrive in bursts — a queue draining forty items is forty of them
  # — and the answer to a burst is one reload.
  @debounce 250

  # The slow half (see `slow_load/1`) and the backstop for the housekeeping
  # plugins that move the counts without announcing it.
  @heartbeat 30_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Books.subscribe_to_book_crud_messages()
      Books.subscribe_to_series_crud_messages()
      People.subscribe_to_person_crud_messages()
      Media.subscribe_to_media_crud_messages()
      # The same signals the header indicator watches, so the two agree
      # rather than the page trailing it by a tick.
      Jobs.subscribe()
      Process.send_after(self(), :heartbeat, @heartbeat)
    end

    {:ok,
     socket
     |> assign(page_title: "Overview", header_title: "Overview", reload_queued: false)
     |> load()
     |> slow_load()}
  end

  @impl Phoenix.LiveView
  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(reload_queued: false) |> load()}
  end

  def handle_info(:heartbeat, socket) do
    Process.send_after(self(), :heartbeat, @heartbeat)

    {:noreply, socket |> load() |> slow_load()}
  end

  # A job moving is the bursty signal — a queue draining forty items sends
  # forty — so those wait for the debounce.
  def handle_info(%JobActivity{}, socket), do: {:noreply, nudge(socket)}
  def handle_info({:notification, :insert, _payload}, socket), do: {:noreply, nudge(socket)}

  # Every CRUD broadcast means the same thing to a page showing only
  # aggregates. Not debounced: each one is a human having just done something.
  def handle_info(_message, socket), do: {:noreply, load(socket)}

  defp nudge(%{assigns: %{reload_queued: true}} = socket), do: socket

  defp nudge(socket) do
    Process.send_after(self(), :reload, @debounce)

    assign(socket, reload_queued: true)
  end

  # The cheap half: about three milliseconds all together, so it can run on
  # every signal.
  defp load(socket) do
    assign(socket,
      queue: Inbox.queue_summary(),
      jobs: Jobs.summary(),
      failures: Jobs.recent_failures(),
      media_problems: Media.problem_counts(),
      watches: Wanted.summary(),
      inventory: inventory()
    )
  end

  # The expensive half, on the heartbeat only. `provider_health/0` walks the
  # matches jsonb of every open queue item and `unreachable_locations/0`
  # stats the filesystem, which on an unmounted NFS share is the call you
  # don't want on a hot path. Neither answer changes job to job.
  defp slow_load(socket) do
    assign(socket,
      providers: Inbox.provider_health(),
      unreachable: Library.unreachable_locations(),
      # Reads every person, author, narrator, book and series and folds each
      # name the way matching does. Not worth doing on every job signal.
      duplicates: Inbox.duplicate_count()
    )
  end

  defp inventory do
    people = People.people_summary()

    %{
      authors: people.authors,
      narrators: people.narrators,
      books: Books.count_books(),
      series: Books.count_series(),
      media: Media.count_media(),
      users: Accounts.count_users()
    }
  end

  @doc """
  The problems worth a row, worst first, each with somewhere to go.

  Assembled here rather than in a context because it spans three of them and
  the ordering is editorial: broken now, then waiting on a human, then
  costing something. Nothing with a count of zero survives.

  Streaming-only recordings are last and quiet. They play fine; what they
  cost is double the disk. Ranking by loudness rather than by count is what
  stops a library made entirely of them opening with a red number every
  morning.
  """
  def problem_rows(assigns) do
    %{media_problems: media, queue: queue, unreachable: unreachable} = assigns

    [
      %{
        words: "Files couldn't be read",
        count: media.missing,
        tone: :red,
        navigate: ~p"/admin/audiobooks?problem=missing"
      },
      %{
        words: "Processing failed",
        count: media.errored,
        tone: :red,
        navigate: ~p"/admin/audiobooks?problem=error"
      },
      %{
        words: location_words(unreachable),
        count: length(unreachable),
        tone: :red,
        navigate: ~p"/admin/locations"
      },
      %{
        words: "Queue items with an issue",
        count: queue.issues,
        tone: :amber,
        # `status=pending` because that is what the count counts: the list
        # must not disagree with the number that was clicked.
        navigate: ~p"/admin/inbox?problem=issue&status=pending"
      },
      %{
        words: "Records the library holds twice",
        count: assigns.duplicates,
        tone: :amber,
        navigate: ~p"/admin/duplicates"
      },
      %{
        words: "Ready to publish, held by the switch",
        count: media.awaiting_switch,
        tone: :zinc,
        navigate: ~p"/admin/settings"
      },
      %{
        words: "Still served by transcoding",
        count: media.streaming_only,
        tone: :zinc,
        navigate: ~p"/admin/audiobooks?problem=streaming"
      }
    ]
    |> Enum.reject(&(&1.count == 0))
  end

  defp location_words([%{kind: kind, name: name, trouble: trouble}]),
    do: "#{String.capitalize(to_string(kind))} #{name} #{trouble_words(trouble)}"

  defp location_words(_several), do: "Locations Ambry can't read"

  defp trouble_words(:missing), do: "can't be read"
  defp trouble_words(:not_a_directory), do: "isn't a folder"
  defp trouble_words(:read_only), do: "is read-only"

  @doc """
  The queues with something in them, so an idle server renders as one
  sentence rather than five rows of zeroes.
  """
  def working_queues(jobs) do
    Enum.reject(jobs.queues, &(&1.running + &1.queued + &1.retrying + &1.failed == 0))
  end

  @doc """
  What the server is doing, in one line.

  Running means wait, queued means it will happen on its own, and retrying
  means a provider said no and it will ask again.
  """
  def work_words(%{running: 0, queued: 0, retrying: 0}), do: "Nothing running."

  def work_words(jobs) do
    [
      jobs.running > 0 && "#{jobs.running} running",
      jobs.queued > 0 && "#{jobs.queued} queued",
      jobs.retrying > 0 && "#{jobs.retrying} waiting to retry"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(", ")
    |> Kernel.<>(".")
  end

  @doc """
  The same, for one queue's row, plus what it gave up on.

  Failures are named here and not in the headline, which answers "is the
  server busy" and a discarded job is not.
  """
  def queue_words(queue) do
    [
      queue.running > 0 && "#{queue.running} running",
      queue.queued > 0 && "#{queue.queued} queued",
      queue.retrying > 0 && "#{queue.retrying} retrying",
      queue.failed > 0 && "#{queue.failed} failed"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(", ")
  end

  @doc """
  Oban's worker name, as the operator would say it.

  Oban stores it *without* the `Elixir.` prefix, so this takes the last
  segment either way.
  """
  def worker_words(worker) when is_binary(worker), do: worker |> String.split(".") |> List.last()

  def failure_time(nil), do: nil
  def failure_time(at), do: Calendar.strftime(at, "%x %X")

  @doc """
  How a provider is answering: how many calls the open queue records, and how
  many of them couldn't be reached.

  A provider with zero calls isn't listed: that would report on the queue's
  contents rather than on the provider.
  """
  def call_words(%{failures: 0, calls: 1}), do: "1 call"
  def call_words(%{failures: 0, calls: calls}), do: "#{calls} calls"
  def call_words(%{failures: failures, calls: calls}), do: "#{failures} of #{calls} failed"

  def provider_tone(%{failures: 0}), do: :ok
  def provider_tone(%{calls: calls, failures: failures}) when failures >= calls, do: :down
  def provider_tone(_some), do: :degraded

  defp count_class(:red), do: "text-red-300"
  defp count_class(:amber), do: "text-amber-300"
  defp count_class(:brand), do: "text-brand-dark"
  defp count_class(_zinc), do: "text-zinc-300"

  defp provider_class(:ok), do: "text-zinc-400"
  defp provider_class(:degraded), do: "text-amber-300"
  defp provider_class(:down), do: "text-red-300"

  attr :label, :string, required: true
  attr :navigate, :string, default: nil
  # The link names where it goes, not what it does: five cards all saying
  # "Open" is five links the eye can't tell apart.
  attr :link_words, :string, default: nil
  # Oban Web is a different application under the same auth, and the overview
  # is a page the operator leaves open, so it opens beside it and says so
  # with the icon.
  attr :new_tab, :boolean, default: false
  slot :inner_block, required: true

  # A card names itself: the label lives inside, at the top, on the text rail
  # (design language §3b).
  defp card(assigns) do
    ~H"""
    <%!-- `min-w-0` is load-bearing. A grid item's automatic minimum size is
          its min-content width, so one long unbroken string in a card makes
          the whole column refuse to shrink. Truncating does not fix it; the
          item has to be allowed to be narrower than its contents. --%>
    <div class="min-w-0 rounded-lg bg-zinc-900 p-4">
      <div class="flex items-baseline justify-between gap-4 pl-3">
        <h3 class="text-sm font-semibold text-zinc-200">{@label}</h3>
        <.link
          :if={@navigate}
          navigate={!@new_tab && @navigate}
          href={@new_tab && @navigate}
          target={@new_tab && "_blank"}
          rel={@new_tab && "noopener"}
          class="text-brand-dark flex items-center gap-1.5 text-sm hover:underline"
        >
          {@link_words}
          <.icon :if={@new_tab} name="fa-arrow-up-right-from-square" class="h-3 w-3 text-current" />
        </.link>
      </div>
      <div class="pt-3">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :tone, :atom, default: :zinc
  attr :role, :string, default: nil
  slot :inner_block, required: true

  # The number leads and the words follow it: this is a page read by
  # scanning, and the label is what the number turned out to be about.
  defp headline_stat(assigns) do
    ~H"""
    <div class="pl-3">
      <p class={["text-3xl font-bold tabular-nums", count_class(@tone)]} data-role={@role}>
        {@count}
      </p>
      <p class="text-sm text-zinc-400">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :count, :integer, required: true
  attr :role, :string, default: nil
  slot :inner_block, required: true

  # A quiet inventory link. Deliberately smaller and flatter than anything
  # above it — it is a fact about the library, never a task.
  defp inventory_stat(assigns) do
    ~H"""
    <.link navigate={@navigate} class="block rounded-md px-3 py-2 hover:bg-white/5">
      <p class="text-xl font-bold tabular-nums text-zinc-200" data-role={@role}>{@count}</p>
      <p class="text-xs text-zinc-400">{render_slot(@inner_block)}</p>
    </.link>
    """
  end

  @doc """
  What the Upcoming card says when nothing is due.

  Not "all clear": nothing is wrong when a book simply isn't out yet. The
  card names the next one instead.
  """
  def next_words(%{next: nil, upcoming_count: 0}), do: "Not waiting for anything."

  def next_words(%{next: nil}), do: "Waiting, but nothing has a date yet."

  def next_words(%{next: watch}) do
    "Nothing out yet. Next: #{watch.edition.title}, " <>
      Calendar.strftime(watch.expected_release_date, "%b %-d")
  end

  # An empty state states itself, on the rail, rather than leaving a blank
  # slab (design language §3b).
  slot :inner_block, required: true

  defp all_clear(assigns) do
    ~H"""
    <p class="pl-3 text-sm text-zinc-400">{render_slot(@inner_block)}</p>
    """
  end
end
