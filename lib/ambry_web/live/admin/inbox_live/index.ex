defmodule AmbryWeb.Admin.InboxLive.Index do
  @moduledoc """
  The curation queue: what discovery found, what it is, and what it claims
  about itself.

  Deliberately plain — the inbox is the surface the admin redesign will be
  built around, so this is the least that makes the workflow usable.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Decisions, only: [tier_words: 1]
  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.Admin.ReturnTo, only: [query: 2]

  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Tier
  alias Ambry.Inbox.InboxItem

  @statuses [:pending, :ignored, :imported]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Inbox", show_header_search: true, ticking: false)
     |> load_items(params)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(search_form: to_form(%{"query" => params["filter"]}, as: :search))
     |> load_items(params)}
  end

  @impl Phoenix.LiveView
  def handle_event("scan", _params, socket) do
    case Inbox.discover_async() do
      {:ok, _job} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Scanning the watched folder. New candidates will show up here."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start a scan.")}
    end
  end

  def handle_event("ignore", %{"id" => id}, socket) do
    {:ok, _item} = id |> Inbox.get_item!() |> Inbox.ignore_item()

    {:noreply, socket |> put_flash(:info, "Ignored. Files untouched.") |> reload()}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    {:ok, _item} = id |> Inbox.get_item!() |> Inbox.restore_item()

    {:noreply, reload(socket)}
  end

  # Nothing in the library moves. The flash says so, because "re-open" beside
  # a row that is wearing an audiobook could otherwise read as undoing the
  # import rather than reopening the paperwork.
  def handle_event("reopen", %{"id" => id}, socket) do
    id
    |> Inbox.get_item!()
    |> Inbox.reopen_item()
    |> case do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Back in the queue. The library is untouched.")
         |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(reason))}
    end
  end

  # Queued, not run here. Importing re-probes every file and then copies every
  # byte, and doing that inside `handle_event` blocked the whole LiveView —
  # the queue froze for the length of a NAS copy, with no sign the click had
  # landed. The row wears the busy overlay instead, same as any other job.
  def handle_event("import", %{"id" => id}, socket) do
    item = Inbox.get_item!(id)

    case Inbox.import_item_async(item) do
      {:ok, job} ->
        message =
          cond do
            job.conflict? -> "Already working on this one."
            replacing?(item) -> "Replacing the files. The row will say when it's done."
            true -> "Adding to the library. The row will say when it's done."
          end

        {:noreply, socket |> put_flash(:info, message) |> reload()}

      # The queue can refuse, but it can't ask: weighing "is this the same
      # book" needs the records side by side, and the answer to it ("link
      # that one instead") can only be given on the form.
      {:error, {:collisions, _findings} = reason} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(reason))}

      {:error, :already_imported} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(:already_imported))}
    end
  end

  # Reports what actually happened. Oban answers a uniqueness conflict with
  # `{:ok, %{job | conflict?: true}}` — an insert that looks successful and
  # discards the job — so the old handlers matched `{:ok, _job}` and flashed
  # success for work that was never queued.
  def handle_event("rescan", %{"id" => id}, socket) do
    id
    |> Inbox.get_item!()
    |> Inbox.rescan_item_async()
    |> case do
      {:ok, job} ->
        message =
          if job.conflict?,
            do: "Already re-reading this one.",
            else: "Re-reading the files and asking the providers again. This can take a while."

        # Reload, or the row the operator just handed to a job keeps looking
        # idle: the overlay is driven by `@progress`, which is only read when
        # the page loads. Nothing else re-read it here, so the cover appeared
        # on the next refresh — after the slow part was over — and in the
        # meantime the row invited clicks on work that was already gone. This
        # also starts the tick that takes the cover back off.
        {:noreply, socket |> put_flash(:info, message) |> reload()}

      # The button is gone from imported rows; this catches a stale tab.
      {:error, :already_imported} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(:already_imported))}
    end
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/inbox?#{patch(socket, filter: query, page: "1")}")}
  end

  def handle_event("filter-status", %{"status" => status}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/inbox?#{patch(socket, status: status, page: "1")}")}
  end

  defp load_items(socket, params) do
    list_opts = params |> get_list_opts() |> Map.put(:problem, parse_problem(params))
    status = parse_status(params["status"])

    # One set of options for the page and for the total, so the queue's "of
    # 355" cannot describe a different query from the rows above it.
    query = [
      status: status,
      filter: list_opts.filter,
      issue: list_opts.problem == "issue"
    ]

    {items, has_more?} =
      Inbox.list_items(query ++ [offset: page_to_offset(list_opts.page), limit: limit()])

    socket
    |> assign(
      items: items,
      # one query for the page, not one per row
      progress: Inbox.progress(items),
      audiobooks: Inbox.audiobooks(items),
      counts: Inbox.count_by_status(),
      status: status,
      list_opts: list_opts,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      page_info: page_info(list_opts, length(items), Inbox.count_items(query)),
      # Built from the full query, not the shared filter+page helpers —
      # those drop the status, so paging out of "Imported" silently landed
      # back on the default view.
      next_page_path: ~p"/admin/inbox?#{page_query(list_opts, status, list_opts.page + 1)}",
      prev_page_path:
        ~p"/admin/inbox?#{page_query(list_opts, status, max(list_opts.page - 1, 1))}"
    )
    |> assign(:statuses, @statuses)
    |> schedule_tick()
  end

  defp reload(socket), do: load_items(socket, patch(socket, []))

  # How often a busy row looks again. Only ticks while something is actually
  # working, so an idle queue costs nothing.
  @tick 2_000

  @impl Phoenix.LiveView
  def handle_info(:refresh_progress, socket) do
    {:noreply, socket |> assign(ticking: false) |> reload()}
  end

  # Without this the overlay is a one-way door: it appears on load and never
  # comes back off, because nothing on this page ever asked again.
  defp schedule_tick(socket) do
    busy? = Enum.any?(socket.assigns.progress, fn {_id, status} -> Inbox.busy?(status) end)

    if busy? and not socket.assigns.ticking do
      Process.send_after(self(), :refresh_progress, @tick)
      assign(socket, ticking: true)
    else
      socket
    end
  end

  @doc """
  Whether a job currently owns this row, so it can say so and refuse to be
  clicked.
  """
  def busy?(status), do: Inbox.busy?(status)

  # What the row's background work is doing. `:done` and `:issue` say nothing
  # here — the row already shows its matches or its issue, and repeating
  # "done" on every settled row is noise that hides the rows that aren't.
  defp progress_label(:importing), do: "Adding to the library…"
  defp progress_label(:working), do: "Working on it…"
  defp progress_label(:retrying), do: "A provider couldn't be reached. Waiting to try again."

  defp progress_label(:queued), do: "Queued"
  defp progress_label(:failed), do: "A background job failed. Try re-scanning."

  defp progress_label(:incomplete), do: "Never finished matching. Try re-scanning."

  defp progress_label(:never_ran), do: "Never read. Try re-probing."
  defp progress_label(_settled), do: nil

  # Blank values are dropped rather than passed as nil: the shared pagination
  # helpers read params with `Map.get(params, "filter", "")`, which only
  # defaults on a *missing* key, so an explicit nil would crash on trim.
  defp patch(socket, overrides) do
    %{
      "filter" => Keyword.get(overrides, :filter, socket.assigns.list_opts.filter),
      "page" => Keyword.get(overrides, :page, to_string(socket.assigns.list_opts.page)),
      "status" => Keyword.get(overrides, :status, to_string(socket.assigns.status || "all")),
      "problem" => Keyword.get(overrides, :problem, to_string(socket.assigns.list_opts[:problem]))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  # The same shape from locals rather than assigns — load_items runs before
  # its assigns exist, so `patch/2` can't be used for the page links.
  @doc """
  The list state, as the params that reproduce it.

  Carried into the form so every way back out of it — imported, ignored, or
  the plain Back button — returns to the tab and page the operator was on.
  Landing them on an unfiltered page one after an import is how "where did my
  queue go" happens.

  The status is stated even when it is "all", because this queue's default tab
  is not its unfiltered one.
  """
  def return_query(assigns),
    do: page_query(assigns.list_opts, assigns.status, assigns.list_opts.page)

  defp page_query(list_opts, status, page) do
    query(list_opts, %{"page" => page, "status" => to_string(status || "all")})
  end

  # The overview counts queue items carrying an issue, and a count the
  # operator can't open is half an answer — so it links here naming the
  # trouble, exactly as the audiobooks list does. An issue is not a status:
  # it cuts across the three buckets (see `Inbox.queue_summary/0`), so it
  # narrows the tab the operator is on rather than replacing it.
  @problems %{
    "issue" => %{
      words: "Queue items with an issue",
      empty: "Nothing here is carrying an issue."
    }
  }

  defp parse_problem(params) do
    problem = params |> Map.get("problem", "") |> String.trim()

    if Map.has_key?(@problems, problem), do: problem
  end

  @doc "What the overview sent the operator here to look at, if anything."
  def problem_words(problem) when is_map_key(@problems, problem), do: @problems[problem].words
  def problem_words(_none), do: nil

  @doc "What an empty list means when it is a problem list that came up dry."
  def problem_empty_words(problem) when is_map_key(@problems, problem),
    do: @problems[problem].empty

  def problem_empty_words(_none), do: nil

  defp parse_status(status) when status in ["pending", "ignored", "imported"],
    do: String.to_existing_atom(status)

  # "all" is the explicit choice; the DEFAULT is pending — the inbox is a
  # work queue, and opening it means "what needs me", not "everything ever".
  defp parse_status("all"), do: nil
  defp parse_status(_anything), do: :pending

  # The segmented filter: the active segment reads as a raised tab, the rest
  # recede. Spans rather than buttons so the existing test selectors (and the
  # click affordance pattern used across this page) stay put.
  defp segment_class(active?) do
    [
      "flex cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-md px-3 py-1.5 font-semibold",
      if(active?,
        do: "bg-zinc-700 text-zinc-100",
        else: "text-zinc-400 hover:text-zinc-100"
      )
    ]
  end

  defp segment_label(:pending), do: "Pending"
  defp segment_label(:ignored), do: "Ignored"
  defp segment_label(:imported), do: "Imported"

  # Pending work glows amber — but only while there IS any; a zero is just a
  # zero.
  defp segment_count_class(status, count) do
    [
      "rounded-full px-1.5 text-xs font-bold tabular-nums",
      case {status, count} do
        {_status, 0} -> "bg-white/5 text-zinc-500"
        {:pending, _n} -> "bg-amber-400/15 text-amber-300"
        _other -> "bg-white/10 text-zinc-400"
      end
    ]
  end

  @doc """
  The row's one badge: what this item is, in the words that vary from row to
  row.

  One badge, not two. A pending row used to wear its status *and* its
  readiness, but inside the Pending tab "pending" is the tab's own word
  repeated on every row — it never told two rows apart. What does is how much
  the row still owes, which is what a settled row's "ready" already said and
  what an outstanding one now says with a number.

  A draft that doesn't exist yet is not a pile of decisions to work through;
  it is one nobody has asked. Counting it as one decision would send the
  operator to a form with nothing on it, so it says what is actually true and
  the card's progress line says what to do about it.
  """
  def state_words(%InboxItem{status: :pending, ready: true}), do: {"ready", :brand}
  def state_words(%InboxItem{status: :pending, draft: nil}), do: {"not prepared", :yellow}

  def state_words(%InboxItem{status: :pending, draft: draft}) do
    case length(Draft.unresolved(draft)) do
      1 -> {"1 decision needed", :yellow}
      n -> {"#{n} decisions needed", :yellow}
    end
  end

  def state_words(%InboxItem{status: status}), do: {to_string(status), status_color(status)}

  defp status_color(:imported), do: :brand
  defp status_color(:ignored), do: :gray

  @doc """
  Whether this item's files have gone away since it was found.
  """
  def missing?(%InboxItem{missing_since: at}), do: not is_nil(at)

  @doc """
  Whether that is worth the row's one badge.

  Only where it changes what can be done. A pending item's files going away
  is what stops it being imported, and it outranks whatever the row still
  owes — the decisions stop mattering when there is nothing to make them
  about. An ignored item was never going to be imported, so the same fact
  says nothing and would cost the row the one word that does.
  """
  def missing_blocks?(%InboxItem{status: :pending} = item), do: missing?(item)
  def missing_blocks?(%InboxItem{}), do: false

  @doc """
  Whether an imported item can go back into the queue.

  The files it would be worked on again have to still be there. A `move`
  placement consumed its source at import time, so those never can, and that
  is the right answer rather than a gap.
  """
  def reopenable?(%InboxItem{status: :imported} = item), do: Inbox.item_files_present?(item)
  def reopenable?(%InboxItem{}), do: false

  @doc """
  What the Import button promises, or why it won't.

  A disabled control that doesn't say what is missing is just a dead button;
  the count comes from the same `Draft.unresolved/1` the form lists in full.
  """
  # Nothing else on the row can be the reason: an item whose files are gone
  # has nothing to import whatever its decisions say.
  def import_title(%InboxItem{missing_since: at}) when not is_nil(at), do: "The files are gone"

  def import_title(%InboxItem{ready: false, draft: nil}),
    do: "Nothing has been proposed for this yet"

  def import_title(%InboxItem{ready: false, draft: draft}) do
    case length(Draft.unresolved(draft)) do
      1 -> "Open it and settle 1 decision first"
      n -> "Open it and settle #{n} decisions first"
    end
  end

  def import_title(item) do
    if replacing?(item), do: "Replace this audiobook's files", else: "Add to the library"
  end

  @doc """
  Whether this item replaces an audiobook the library already has.

  The queue's Import is the one control that acts without the form being
  opened, so it has to name what it will do: a replacement takes an
  audiobook's files away and puts these in their place. What that costs — the
  existing files, unless they are a known hardlink — is a question about the
  disk, and it stays on the form where it can be answered.
  """
  def replacing?(%InboxItem{draft: draft}), do: Replacement.replacing?(draft && draft.replacement)

  # The card's left edge carries the item's state — a 4px rail reads from
  # across the room and renders crisp at any DPI, unlike hairline borders.
  # Amber = needs the operator, lime = ready/done, dim = out of the queue.
  defp rail_class(%{status: :pending, ready: true}), do: "border-l-4 border-brand-dark"
  defp rail_class(%{status: :pending}), do: "border-l-4 border-amber-400"
  defp rail_class(%{status: :imported}), do: "border-brand-dark/40 border-l-4"
  defp rail_class(_item), do: "border-l-4 border-zinc-700"

  @doc """
  The candidate's name — usually the release name, and the most recognizable
  thing about it.
  """
  def item_name(item), do: InboxItem.name(item)

  @doc """
  A one-line summary of what the file says it is, which is what makes an item
  identifiable at a glance before anything has been matched.
  """
  def tag_summary(%InboxItem{tags: tags}) when is_map(tags) do
    [
      tags["book_title"],
      join_names(tags["authors"]),
      narrated_by(tags["narrators"]),
      series_label(tags)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  def tag_summary(_item), do: ""

  defp narrated_by(nil), do: nil
  defp narrated_by([]), do: nil
  defp narrated_by(names), do: "read by #{join_names(names)}"

  defp join_names(nil), do: nil
  defp join_names([]), do: nil
  defp join_names(names), do: Enum.join(names, ", ")

  defp series_label(%{"series" => nil}), do: nil
  defp series_label(%{"series" => series, "series_number" => nil}), do: series
  defp series_label(%{"series" => series, "series_number" => number}), do: "#{series} ##{number}"
  defp series_label(_tags), do: nil

  @doc """
  What the files actually are, as probed — the facts, as opposed to the
  claims in `tag_summary/1`.
  """
  def probe_summary(%InboxItem{probe: probe}), do: probe |> probe_facts() |> Enum.join(" · ")

  def file_count(%InboxItem{files: files}), do: length(files)

  @doc """
  The proposed work and recording, each with how sure the match is.

  Both are shown even when one is missing: knowing that nothing matched at
  the recording level is itself the useful thing.
  """
  def match_summary(%InboxItem{matches: matches} = item) when is_map(matches) do
    Enum.map(["work", "recording"], fn level ->
      # `|| []` on both lines: a level present without candidates used to
      # crash `List.first/1` here, taking the whole page down over one
      # malformed row, while the line below already guarded for it.
      candidates = get_in(matches, [level, "candidates"]) || []

      %{
        level: level,
        best: List.first(candidates),
        alternatives: max(length(candidates) - 1, 0),
        tier: level_tier(item, level),
        confidence: get_in(matches, [level, "confidence"]),
        query: get_in(matches, [level, "query"])
      }
    end)
  end

  def match_summary(_item), do: []

  # The draft is the live truth: its tier moves when the operator decides,
  # where `matches[level]["confidence"]` was frozen at match time — so the
  # queue used to keep calling an item "unsure" after a human had settled it,
  # and could disagree with the form after a background re-match. The
  # fallback covers the moment between matching and the draft existing.
  #
  # One vocabulary with the form, or the two drift: the queue says what the
  # form's rail says, in the same four words.
  defp level_tier(%InboxItem{draft: %Draft{work: %{} = work}}, "work"), do: Tier.of(work)

  defp level_tier(%InboxItem{draft: %Draft{recording: %{} = recording}}, "recording"),
    do: Tier.of(recording)

  defp level_tier(%InboxItem{matches: matches}, level) do
    case get_in(matches, [level, "confidence"]) || 0.0 do
      sure when sure >= 0.6 -> :unreviewed
      _doubted_or_nothing -> :waiting
    end
  end

  @doc "What a match level is called on the card — the data keys stay work/recording."
  def level_word("work"), do: "book"
  def level_word("recording"), do: "audiobook"

  def candidate_label(nil), do: "no match"

  def candidate_label(candidate) do
    [candidate["title"], join_names(candidate["authors"])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" by ")
  end

  def candidate_origin(nil), do: nil
  def candidate_origin(%{"source" => "local"}), do: "already in the library"
  def candidate_origin(%{"provider_name" => name}) when is_binary(name), do: name
  def candidate_origin(%{"source" => "provider:" <> id}), do: id
  def candidate_origin(_candidate), do: nil

  @doc """
  When the operator imported this item.

  `updated_at` is the moment the status changed, and nothing writes to an
  item afterwards — a scan skips imported items outright, and every write
  path refuses one. It is already what the imported tab sorts by.
  """
  def imported_at(%InboxItem{updated_at: at}), do: at

  # The library's own state, which only an imported row can have: the badges
  # the audiobooks list wears, in the same colors, on the cover it belongs to.
  # `:ready` renders nothing — every audiobook is meant to be ready, so saying
  # it on all of them hides the ones that aren't.
  defp library_status_color(:pending), do: :yellow
  defp library_status_color(:processing), do: :blue
  defp library_status_color(:error), do: :red
end
