defmodule AmbryWeb.Admin.InboxLive.Index do
  @moduledoc """
  The curation queue: what discovery found, what it is, and what it claims
  about itself.

  Deliberately plain — the inbox is the surface the admin redesign will be
  built around, so this is the least that makes the workflow usable.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.Inbox
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library.Location

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
           "Scanning the watched folder. Nothing is moved or changed — new candidates just show up here."
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

  def handle_event("import", %{"id" => id}, socket) do
    id
    |> Inbox.get_item!()
    |> Inbox.import_item()
    |> case do
      {:ok, _media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added to the library. Files were left where they are.")
         |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(reason))}
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
            else:
              "Re-reading the files and asking the providers again — this one is slow on purpose."

        {:noreply, put_flash(socket, :info, message)}

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
     push_patch(socket,
       to: ~p"/admin/inbox?#{patch(socket, status: status, ready: nil, page: "1")}"
     )}
  end

  def handle_event("filter-ready", _params, socket) do
    ready = if !socket.assigns.ready, do: "true"

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/inbox?#{patch(socket, ready: ready, status: "pending", page: "1")}"
     )}
  end

  defp load_items(socket, params) do
    list_opts = get_list_opts(params)
    status = parse_status(params["status"])
    ready = parse_ready(params["ready"])

    {items, has_more?} =
      Inbox.list_items(
        status: status,
        ready: ready,
        filter: list_opts.filter,
        offset: page_to_offset(list_opts.page),
        limit: limit()
      )

    socket
    |> assign(
      items: items,
      # one query for the page, not one per row
      progress: Inbox.progress(items),
      counts: Inbox.count_by_status(),
      ready_count: Inbox.count_ready(),
      ready: ready,
      status: status,
      list_opts: list_opts,
      has_next: has_more?,
      has_prev: list_opts.page > 1,
      # Built from the full query, not the shared filter+page helpers —
      # those drop status and ready, so paging out of "Imported" silently
      # landed back on the default view.
      next_page_path:
        ~p"/admin/inbox?#{page_query(list_opts, status, ready, list_opts.page + 1)}",
      prev_page_path:
        ~p"/admin/inbox?#{page_query(list_opts, status, ready, max(list_opts.page - 1, 1))}"
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
  defp progress_label(:working), do: "Working on it…"
  defp progress_label(:retrying), do: "A provider couldn't be reached — waiting to try again."

  defp progress_label(:queued), do: "Queued"
  defp progress_label(:failed), do: "A background job failed — try re-scanning."

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
      "ready" =>
        Keyword.get(overrides, :ready, socket.assigns.ready && to_string(socket.assigns.ready))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  # The same shape from locals rather than assigns — load_items runs before
  # its assigns exist, so `patch/2` can't be used for the page links.
  defp page_query(list_opts, status, ready, page) do
    %{
      "filter" => list_opts.filter,
      "page" => to_string(page),
      "status" => to_string(status || "all"),
      "ready" => ready && to_string(ready)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp parse_status(status) when status in ["pending", "ignored", "imported"],
    do: String.to_existing_atom(status)

  # "all" is the explicit choice; the DEFAULT is pending — the inbox is a
  # work queue, and opening it means "what needs me", not "everything ever".
  defp parse_status("all"), do: nil
  defp parse_status(_anything), do: :pending

  defp parse_ready("true"), do: true
  defp parse_ready(_anything), do: nil

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

  # Pending work glows amber and settled-but-unimported glows lime — but only
  # while there IS any; a zero is just a zero.
  defp segment_count_class(status, count) do
    [
      "rounded-full px-1.5 text-xs font-bold tabular-nums",
      case {status, count} do
        {_status, 0} -> "bg-white/5 text-zinc-500"
        {:pending, _n} -> "bg-amber-400/15 text-amber-300"
        {:ready, _n} -> "bg-brand-dark/15 text-lime-300"
        _other -> "bg-white/10 text-zinc-400"
      end
    ]
  end

  # Row actions wear words. An unlabeled 16px icon is neither a label nor a
  # touch target, and the queue's actions are consequential enough to name.
  defp action_class(tone) do
    [
      "flex cursor-pointer items-center justify-center gap-1 whitespace-nowrap rounded-md px-2 py-1 text-xs font-semibold transition-colors sm:w-28",
      case tone do
        :brand ->
          "bg-brand-dark/10 text-lime-300 hover:bg-brand-dark/20"

        :danger ->
          "bg-white/5 text-zinc-400 hover:bg-red-400/10 hover:text-red-300"

        :neutral ->
          "bg-white/5 text-zinc-300 hover:bg-white/10 hover:text-zinc-100"
      end
    ]
  end

  defp status_color(:pending), do: :yellow
  defp status_color(:imported), do: :brand
  defp status_color(:ignored), do: :gray

  # The card's left edge carries the item's state — a 4px rail reads from
  # across the room and renders crisp at any DPI, unlike hairline borders.
  # Amber = needs the operator, lime = ready/done, dim = out of the queue.
  defp rail_class(%{status: :pending, ready: true}), do: "border-l-4 border-brand-dark"
  defp rail_class(%{status: :pending}), do: "border-l-4 border-amber-400"
  defp rail_class(%{status: :imported}), do: "border-brand-dark/40 border-l-4"
  defp rail_class(_item), do: "border-l-4 border-zinc-700"

  # Where an item came from is what decides its custody at import — whether
  # the file gets brought into the library or referenced where it lies — so
  # it's worth reading off the row.
  defp location_label(%Location{name: name, kind: kind}), do: "#{name} · #{kind_word(kind)}"
  defp location_label(nil), do: "ad-hoc scan · adopted in place"

  # "imported" would now read as the item status; this is custody — what
  # import will do with the bytes.
  defp kind_word(:downloads), do: "brought in on import"
  defp kind_word(:external_collection), do: "adopted in place"
  defp kind_word(:library_root), do: "already in the library tree"

  defp location_color(%Location{kind: :downloads}), do: "bg-blue-400/15 text-blue-300"

  defp location_color(_other), do: "bg-white/10 text-zinc-300"

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
  def probe_summary(%InboxItem{probe: probe}) when is_map(probe) do
    [
      probe["duration"] && format_timecode(Decimal.new(probe["duration"])),
      probe["codec"],
      probe["chapters"] && probe["chapters"] > 0 && "#{probe["chapters"]} chapters",
      probe["seek_accuracy"] == "approximate" && "inexact seeking"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  def probe_summary(_item), do: ""

  def file_count(%InboxItem{files: files}), do: length(files)

  @doc """
  The proposed work and recording, each with how sure the match is.

  Both are shown even when one is missing: knowing that nothing matched at
  the recording level is itself the useful thing.
  """
  def match_summary(%InboxItem{matches: matches}) when is_map(matches) do
    Enum.map(["work", "recording"], fn level ->
      # `|| []` on both lines: a level present without candidates used to
      # crash `List.first/1` here, taking the whole page down over one
      # malformed row, while the line below already guarded for it.
      candidates = get_in(matches, [level, "candidates"]) || []

      %{
        level: level,
        best: List.first(candidates),
        alternatives: max(length(candidates) - 1, 0),
        confidence: get_in(matches, [level, "confidence"]) || 0.0,
        query: get_in(matches, [level, "query"])
      }
    end)
  end

  def match_summary(_item), do: []

  def candidate_label(nil), do: "no match"

  def candidate_label(candidate) do
    [candidate["title"], join_names(candidate["authors"])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" — ")
  end

  def candidate_origin(nil), do: nil
  def candidate_origin(%{"source" => "local"}), do: "already in library"
  def candidate_origin(%{"provider_name" => name}) when is_binary(name), do: name
  def candidate_origin(%{"source" => "provider:" <> id}), do: id
  def candidate_origin(_candidate), do: nil

  @doc """
  Confidence as a word. A number invites false precision; what the operator
  needs is whether this one can be waved through.
  """
  def confidence_label(confidence) when confidence >= 0.85, do: {"near-certain", :brand}
  def confidence_label(confidence) when confidence >= 0.6, do: {"likely", :blue}
  def confidence_label(confidence) when confidence > 0.0, do: {"unsure", :yellow}
  def confidence_label(_confidence), do: {"no match", :gray}
end
