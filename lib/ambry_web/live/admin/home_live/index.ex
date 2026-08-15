defmodule AmbryWeb.Admin.HomeLive.Index do
  @moduledoc """
  The admin landing page: what needs the operator, and whether the server is
  all right.

  ## What changed, and why

  This used to be six counts — books, series, people, audiobooks, files, users
  — each linking to its list. Every one of those numbers only ever goes up,
  and none of them has ever caused anybody to do anything. They were nav links
  wearing numbers, which is why the page stopped being read.

  The test a tile has to pass now: **it can be in a bad state, and clicking it
  lands where you would fix it.** The inventory counts survive at the bottom
  as one quiet strip, because knowing the library's size is worth a glance
  even though it is never a task.

  ## Landing here rather than on the inbox

  The inbox is the daily loop, so landing on it was the obvious alternative
  and it was rejected: the inbox is a work queue over discovered files, and it
  structurally cannot answer *did something break while I wasn't looking*.
  Failed jobs, a source whose NAS is unmounted, a provider rate-limiting every
  call, recordings whose files have gone missing — none of those are inbox
  rows. A queue as a landing page also drops the operator into the middle of a
  task on every login, including the logins that were only meant to be a
  check.

  What landing on the inbox was actually buying — one click — is bought
  instead by the pending badge on the nav item, which works from every page.

  ## Ordering is by who is waiting on whom

  Four sections, loudest first. **Needs you** is work that will not move
  without a human. **Background work** is the server's turn, including the
  part of the inbox nobody has asked about yet; it is the 3f ambient status
  widget, and it exists because "still working", "done", and "failed and
  you'll never know" looked identical from here. **Problems** is what is
  wrong. **Library** is the inventory strip.

  ## Zero means different things in different sections

  A queue with nothing in it is reported (that *is* the answer to "is the
  server busy"); a problem with a count of zero is not, because a card of
  green zeroes teaches the eye to skip it and the one row that matters goes
  with it. Each section says so in its own empty state instead.
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

  # Every CRUD broadcast lands here; they all mean the same thing to a page
  # that is only ever showing aggregates. Not debounced: one of these is a
  # human having just done something, and making them wait a quarter second
  # to see it buys nothing.
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
      inventory: inventory()
    )
  end

  # The expensive half, on the heartbeat only. `provider_health/0` walks the
  # matches jsonb of every open queue item — 39ms against 343 of them — and
  # `unreachable_locations/0` stats the filesystem, which on an unmounted NFS
  # share is exactly the call you don't want on a hot path. Neither answer
  # changes between one job and the next.
  defp slow_load(socket) do
    assign(socket,
      providers: Inbox.provider_health(),
      unreachable: Library.unreachable_locations()
    )
  end

  defp inventory do
    people = People.count_people()

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
  the ordering is an editorial decision, not a fact about any one of them:
  broken now, then waiting on a human, then costing something. Nothing with a
  count of zero survives.

  **Streaming-only recordings are deliberately last and deliberately quiet.**
  They play fine; what they cost is double the disk, and clearing one means
  relinking it to its source. Ranking them by loudness rather than by count
  keeps a library that is *entirely* legacy — which production is — from
  opening every morning with a red number at the top of the page.
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
        navigate: ~p"/admin/inbox"
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

  The three states are named separately because they answer different
  questions: running means wait, queued means it will happen on its own, and
  retrying means a provider said no and it will ask again.
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

  Failures are named here and not in the headline: the headline answers "is
  the server busy", which a discarded job is not, and the failures have a
  card of their own that says what they were.
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

  Oban stores it *without* the `Elixir.` prefix, so matching on one was a
  clause that never fired and every failure wore its full module path. Take
  the last segment and don't care how it was written.
  """
  def worker_words(worker) when is_binary(worker), do: worker |> String.split(".") |> List.last()

  def failure_time(nil), do: nil
  def failure_time(at), do: Calendar.strftime(at, "%x %X")

  @doc """
  How a provider is answering: how many calls the open queue records, and how
  many of them couldn't be reached.

  A provider with zero calls isn't listed at all — it would be reporting on
  the queue's contents, not on the provider — so silence here means nothing
  has asked it yet, which the empty state says outright.
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
  # The link names where it goes, not what it does. Five cards all saying
  # "Open" is five links the eye can't tell apart, and two of them land on
  # the Oban dashboard while the others don't.
  attr :link_words, :string, default: nil
  # Oban Web is a different application living under the same auth, and the
  # overview is a page the operator leaves open. Sending them there in the
  # same tab costs them the thing they were watching, so it opens beside it —
  # and says so with the icon, because a link that behaves differently has to
  # look different before it is clicked.
  attr :new_tab, :boolean, default: false
  slot :inner_block, required: true

  # A card names itself: the label lives inside, at the top, on the text rail
  # (design language §3b).
  defp card(assigns) do
    ~H"""
    <%!-- `min-w-0` is load-bearing, not decoration. A grid item's automatic
          minimum size is the min-content width of what's inside it, so one
          long unbroken string anywhere in a card — an error, a path, a
          provider id — makes the whole column refuse to shrink and pushes
          the page sideways on a phone. Measured: 711px of card in a 390px
          viewport. Truncating the string does not fix it; the item has to
          be allowed to be narrower than its contents. --%>
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

  # An empty state states itself, on the rail, rather than leaving a blank
  # slab (design language §3b).
  slot :inner_block, required: true

  defp all_clear(assigns) do
    ~H"""
    <p class="pl-3 text-sm text-zinc-400">{render_slot(@inner_block)}</p>
    """
  end
end
