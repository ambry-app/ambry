defmodule AmbryWeb.Admin.InboxLive.Form do
  @moduledoc """
  The staged import form: everything this release will become, before any of
  it is real.

  Built on one invariant: **an import is a tree of decisions, and import is
  possible iff every decision is resolved.** The button at the bottom reads
  `Draft.unresolved/1` and nothing else, which is what guarantees the form
  never offers an action that fails.

  Two kinds of interaction. Typing is ordinary form input, autosaved on
  change, so there is never an unsaved edit to lose. Choosing (which
  candidate, which identity, who is behind a credit) is a named event that
  transforms the stored draft through `Draft.Edit`.

  A credit reads as one line ("Written by" / "Read by") and the humans behind
  it live in their own section, one card each: asked inside every credit, the
  personhood question charges every ordinary import for an answer only a
  handful have, and prints a person twice when an author reads their own book.
  What is left on the credit is "This is a pen name".
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.ChapterEditor
  import AmbryWeb.Admin.Decisions

  alias Ambry.Books
  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Chapters
  alias Ambry.Inbox.Draft.Destination
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Replacement
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.Tier
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Library.Placement
  alias Ambry.Media
  alias Ambry.Media.Chapters.Merge
  alias AmbryWeb.Admin.NewPerson
  alias AmbryWeb.Admin.ReturnTo
  alias AmbryWeb.Components.EntityResolver
  alias Phoenix.LiveView.AsyncResult

  require Logger

  @impl Phoenix.LiveView
  def mount(%{"id" => id} = params, _session, socket) do
    case Inbox.fetch_item(id) do
      {:ok, item} -> mount_item(item, params, socket)
      {:error, :not_found} -> gone(params, socket)
    end
  end

  # Regrouping replaces items rather than editing them, so the id in the
  # address bar can outlive the item. Back after a split is the queue
  # working, not a 404.
  defp gone(params, socket) do
    {:ok,
     socket
     |> put_flash(
       :info,
       "That item is gone. Splitting and combining replace items with new ones."
     )
     |> push_navigate(to: return_to(params))}
  end

  defp mount_item(item, params, socket) do
    {:ok, item} = Inbox.prepare_draft(item)

    {:ok,
     socket
     |> assign(page_title: InboxItem.name(item))
     |> assign(researching: nil, retrying: nil, enriching: nil)
     # What the in-flight search asked for. The stored query only updates
     # when results land, so rendering it describes the previous search for
     # the whole round trip.
     |> assign(research_fields: %{})
     # View state keyed by person key; the results are evidence and live on
     # the item. A map rather than one key, because a full cast is fifteen
     # people searched at once.
     |> assign(searching_people: %{}, photos_expanded: %{})
     |> assign(ticking: false)
     # The pending chapter-title fetch, and which ASIN's titles were last
     # poured — the chips' chosen state.
     |> assign(chapter_import: nil, chapters_applied_asin: nil)
     # Where the operator came from, so every way out of this form — imported,
     # ignored, or the plain Back button — returns to the tab and page they
     # were on rather than an unfiltered page one.
     |> assign(return_to: return_to(params))
     |> attach_hook(:refuse_while_busy, :handle_event, &refuse_while_busy/3)
     |> attach_hook(:refuse_when_imported, :handle_event, &refuse_when_imported/3)
     |> load(item)}
  end

  # The list state the operator arrived with, echoed back as a path. The
  # whitelist is `ReturnTo`'s, so a form opened from a narrowed queue returns
  # to that queue.
  defp return_to(params), do: ReturnTo.path(~p"/admin/inbox", ReturnTo.list_params(params))

  # An imported item's draft is the record of what was imported. The banner
  # and `inert` explain; this enforces, since a stale tab can send anything.
  @view_events ~w(toggle-photos)

  defp refuse_when_imported(event, _params, socket) do
    if socket.assigns.read_only and event not in @view_events do
      {:halt, put_flash(socket, :error, Inbox.describe_error(:already_imported))}
    else
      {:cont, socket}
    end
  end

  # The overlay explains; this enforces. Matching rebuilds an untouched draft
  # when a retried provider answers.
  defp refuse_while_busy(event, _params, socket) do
    if busy?(socket) do
      Logger.debug(fn -> "Inbox form: refusing #{event} while a job owns item" end)
      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  @doc """
  Whether anything owns this form right now — a matching job, or the
  operator's own import.

  One predicate for both, because the form's answer is the same either way.
  """
  def busy?(%{assigns: assigns}), do: busy?(assigns)
  def busy?(%{busy: busy}), do: busy

  # How often a busy form looks again. Only ticks while a job is actually on
  # this item, so an idle form costs nothing.
  @tick 2_000

  @impl Phoenix.LiveView
  def handle_info(:refresh_job, socket) do
    # Reload rather than just re-reading the status: the job that finished may
    # have rebuilt this very draft, and the form has to show what it built.
    {:noreply,
     socket
     |> assign(ticking: false)
     |> load(Inbox.get_item!(socket.assigns.item.id))}
  end

  defp schedule_tick(socket) do
    if socket.assigns.busy and not socket.assigns.ticking do
      Process.send_after(self(), :refresh_job, @tick)
      assign(socket, ticking: true)
    else
      socket
    end
  end

  @doc """
  What the job on this item is doing, in the words the overlay uses.
  """
  # Naming the slow part: a multi-file release is re-probed file by file and
  # then every one of them is placed.
  def busy_label(:importing), do: "Adding to the library…"
  def busy_label(:working), do: "Matching…"
  def busy_label(:retrying), do: "A provider couldn't be reached. Retrying…"
  def busy_label(:queued), do: "Queued for matching…"
  def busy_label(_idle), do: "Working…"

  @doc """
  What a level's search box shows: the query in flight while one is running,
  and the last one asked otherwise.

  The stored query is only written when results land, so rendering it during
  the round trip would describe the previous search.
  """
  def search_fields(level, level, in_flight, _seeded), do: in_flight
  def search_fields(_researching, _level, _in_flight, seeded), do: seeded

  # The query keys a search form can submit, the same set
  # `Provider.Query.from_fields/1` reads.
  @query_keys ~w(title author narrator)

  defp submitted_fields(params), do: Map.take(params, @query_keys)

  # What each level's boxes hold when no search is in flight.
  #
  # The stored query is what was last asked, and an ASIN match stores a shape
  # this form has no box for, so it falls back to the hints matching used and
  # a box always holds something submittable.
  #
  # Wholesale, never per key: merging hints into a stored query would put
  # back an author the operator deliberately cleared.
  defp search_seeds(item) do
    hints = Inbox.hints(item)

    from_hints =
      %{"title" => hints[:title], "author" => hints[:author], "narrator" => hints[:narrator]}
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    draft = item.draft

    %{
      "work" => seeded_fields(draft && draft.work, from_hints),
      "recording" => seeded_fields(draft && draft.recording, from_hints)
    }
  end

  defp seeded_fields(nil, from_hints), do: from_hints

  defp seeded_fields(decision, from_hints) do
    case Map.take(decision.query_fields || %{}, @query_keys) do
      no_text_fields when map_size(no_text_fields) == 0 -> from_hints
      stored -> stored
    end
  end

  @doc """
  What a level's search is looking for, for the scrim that covers it.

  Named rather than a bare "Searching…", so the operator can see the click
  landed on the search they meant.
  """
  def searching_label(fields) do
    case (fields || %{})["title"] do
      title when is_binary(title) and title != "" -> "Looking for #{title}…"
      _untitled -> "Searching…"
    end
  end

  # What a person is currently called, which is what a re-search asks about.
  defp person_name(draft, key) do
    case Draft.person(draft, key) do
      nil -> nil
      person -> Field.value(person.name)
    end
  end

  @doc "One person's provider records, for their own card."
  def person_records(item, key), do: get_in(item.matches, ["people", key, "candidates"]) || []

  @doc "What each person provider said when asked about them."
  def person_outcomes(item, key), do: get_in(item.matches, ["people", key, "providers"]) || []

  @doc """
  Searches for every person nobody has asked about — the edit forms'
  control, sharing their implementation.
  """
  def search_all_people(item, searching) do
    item |> unsearched_people(searching) |> NewPerson.search_all(%{})
  end

  @doc """
  The people on this draft nobody has asked the databases about, as
  `{key, name}` — what the People section's "Search all" presses.

  Matching asks about everyone an item arrives with, so this fills only when
  the operator adds credits.
  """
  def unsearched_people(item, searching) do
    for group <- Draft.people_groups(item.draft),
        person <- group.people,
        person.mode == :create,
        person_records(item, person.key) == [],
        not Map.has_key?(searching, person.key),
        name = Field.value(person.name),
        name not in [nil, ""] do
      {person.key, name}
    end
  end

  @doc """
  The people the library already has by this human's name.

  Collected by matching whenever a credited name is already in the library:
  the author who turns up narrating, whose name the credit's typeahead cannot
  offer because the identity they need doesn't exist yet.
  """
  def person_locals(item, key), do: get_in(item.matches, ["people", key, "local"]) || []

  @doc """
  The name this person's records were searched for.

  The person level's `query_fields`, so the search box holds the query rather
  than the person's name decision. In flight it is the name just submitted.
  """
  def person_query_name(item, key, searching) do
    case Map.get(searching, key) do
      name when is_binary(name) -> name
      _not_searching -> get_in(item.matches, ["people", key, "name"])
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"inbox_item" => params}, socket) do
    params = curate_chapter_params(params, socket.assigns.item)

    # Autosave, so a click on any choice control below cannot discard typing.
    #
    # The one write that cannot be replayed against a newer draft, so it is
    # the one that can come back refused. Reloading is the honest answer.
    case Inbox.update_draft(socket.assigns.item, params["draft"] || %{}) do
      {:ok, item} ->
        {:noreply, load(socket, item)}

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Something else changed this item while you were typing. Reloaded; check the last thing you entered."
         )
         |> load(Inbox.get_item!(socket.assigns.item.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("choose-field", %{"section" => section, "field" => field} = params, socket) do
    {:noreply,
     edit(socket, &Draft.Edit.choose_field(&1, atom(section), atom(field), params["key"]))}
  end

  def handle_event("waive-field", %{"section" => section, "field" => field}, socket) do
    {:noreply, edit(socket, &Draft.Edit.waive_field(&1, atom(section), atom(field)))}
  end

  # The decision above every other one: these files are a better copy of
  # something the library already has. A blank id is the surrounding form
  # reporting itself for some other reason, not an answer.
  def handle_event("replace-recording", %{"media_id" => id}, socket) do
    case to_int(id) do
      nil -> {:noreply, socket}
      media_id -> {:noreply, edit(socket, &Draft.Edit.replace_recording(&1, media_id))}
    end
  end

  def handle_event("new-recording", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.new_recording/1)}
  end

  def handle_event("link-book", %{"book_id" => id}, socket) do
    item = socket.assigns.item

    case to_int(id) do
      nil -> {:noreply, socket}
      book_id -> {:noreply, edit(socket, &Draft.Edit.link_book(&1, item, book_id))}
    end
  end

  def handle_event("new-book", _params, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.new_book(&1, item))}
  end

  def handle_event("toggle-source", %{"level" => level} = params, socket) do
    item = socket.assigns.item
    ref = {params["source"], to_string(params["id"])}

    case Enum.find(Seed.records(item, level), &(Inbox.record_ref(&1) == ref)) do
      nil ->
        {:noreply, socket}

      record ->
        socket = edit(socket, &Draft.Edit.toggle_source(&1, item, atom(level), record))

        # A record nobody asked about is a summary, so ticking it is when its
        # description and cover (and, for a work, its editions) are fetched.
        {:noreply, enrich(socket, level, record)}
    end
  end

  # "None of these" — a real answer at either level, and the only one available
  # when nothing a provider returned describes the release.
  def handle_event("uncatalogued", params, socket) do
    item = socket.assigns.item
    level = atom(params["level"] || "recording")
    {:noreply, edit(socket, &Draft.Edit.uncatalogued(&1, item, level))}
  end

  def handle_event("move-credit", %{"section" => s, "index" => i, "direction" => d}, socket) do
    {:noreply, edit(socket, &Draft.Edit.move_credit(&1, atom(s), to_int(i), direction(d)))}
  end

  def handle_event("move-series", %{"index" => i, "direction" => d}, socket) do
    {:noreply, edit(socket, &Draft.Edit.move_series(&1, to_int(i), direction(d)))}
  end

  # ── chapters ───────────────────────────────────────────────────────────
  #
  # The media form's event vocabulary. Take applies fetched titles through
  # `Draft.Edit.set_chapters/2`, so the answer survives reseeds.

  def handle_event("fetch-chapter-titles", %{"asin" => asin}, socket) do
    chip =
      socket.assigns.item
      |> chapter_chips(socket.assigns.chapters_applied_asin)
      |> Enum.find(&(&1.asin == asin))

    if chip do
      {:noreply,
       socket
       |> assign(chapter_import: pending_import(chip))
       |> start_async(:chapter_titles, fn -> fetch_chapter_titles(asin) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("apply-chapter-titles", _params, socket) do
    showing = draft_chapter_rows(socket.assigns.item)

    with %{chip: chip, result: %AsyncResult{ok?: true, result: fetched}} <-
           socket.assigns.chapter_import,
         # one-to-one or not at all — an operator call; a mismatched list
         # stays visible in the proposed column but is never poured
         true <- takeable?(fetched.incoming, showing) do
      {merged, _alignment} = Merge.titles(showing, fetched.incoming, :provider)

      {:noreply,
       socket
       |> edit(&Draft.Edit.set_chapters(&1, merged))
       |> assign(chapter_import: nil, chapters_applied_asin: chip.asin)}
    else
      _not_takeable -> {:noreply, socket}
    end
  end

  def handle_event("cancel-chapter-import", _params, socket) do
    {:noreply, assign(socket, chapter_import: nil)}
  end

  # The way back to the machine's value, which every other decision has.
  # Taking a value the rows already hold still counts as reviewing it.
  def handle_event("take-file-chapters", _params, socket) do
    case Seed.file_chapters(socket.assigns.item) do
      %Chapters{chapters: [_row | _rest] = rows, chapter_marker_source: source} ->
        {:noreply,
         socket
         |> edit(&Draft.Edit.set_chapters(&1, rows, source))
         |> assign(chapter_import: nil, chapters_applied_asin: nil)}

      _nothing_to_take ->
        {:noreply, socket}
    end
  end

  def handle_event("research", %{"level" => level} = params, socket) do
    item = socket.assigns.item

    {:noreply,
     socket
     |> assign(researching: level, research_fields: submitted_fields(params))
     |> start_async({:research, level}, fn -> Inbox.research(item, level, params) end)}
  end

  def handle_event("retry-provider", %{"level" => level, "provider" => provider}, socket) do
    item = socket.assigns.item

    {:noreply,
     socket
     |> assign(retrying: provider)
     |> start_async({:retry, level}, fn -> Inbox.retry_provider(item, level, provider) end)}
  end

  def handle_event("credit-change", %{"section" => section, "index" => i} = params, socket) do
    section = atom(section)
    index = to_int(i)
    id = to_int(params["identity_id"])
    item = socket.assigns.item

    {:noreply,
     edit(socket, fn draft ->
       if id do
         Draft.Edit.link_credit(draft, section, index, id)
       else
         draft
         |> Draft.Edit.create_credit(section, index)
         |> Draft.Edit.rename_credit(section, index, params["name"] || "")
         # A person named for the first time (an added row's first real name
         # mints their key) needs their decision minted before approval can
         # resolve it.
         |> Draft.Edit.sync_people(item)
       end
     end)}
  end

  def handle_event("split", params, socket) do
    case Inbox.split_item(socket.assigns.item, atom(params["by"] || "file")) do
      {:ok, children} ->
        {:noreply,
         socket
         |> put_flash(:info, "Split into #{length(children)} items. Scanning each one now.")
         |> push_navigate(to: ~p"/admin/inbox")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't split this item.")}
    end
  end

  # Recomputed here rather than taken from the assigns: the items being
  # combined are the ones waiting under that folder now.
  def handle_event("combine", _params, socket) do
    case Inbox.combine_item(socket.assigns.item) do
      {:ok, combined} ->
        {:noreply,
         socket
         |> put_flash(:info, "Combined into one item. Reading the files now.")
         |> push_navigate(to: ~p"/admin/inbox/#{combined}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't combine these items.")}
    end
  end

  # One file in or out of the audiobook. The item is re-read either way, so
  # the form goes busy and comes back with the recording's new length.
  def handle_event("toggle-file", %{"file" => file}, socket) do
    item = socket.assigns.item

    result =
      if InboxItem.excluded?(item, file),
        do: Inbox.include_file(item, file),
        else: Inbox.exclude_file(item, file)

    case result do
      {:ok, item} ->
        {:noreply, load(socket, item)}

      {:error, :last_file} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(:last_file))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't change that file.")}
    end
  end

  def handle_event("add-credit", %{"section" => s}, socket) do
    {:noreply, edit(socket, &Draft.Edit.add_credit(&1, atom(s)))}
  end

  def handle_event("add-series", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.add_series/1)}
  end

  def handle_event("add-group", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.add_group/1)}
  end

  def handle_event("remove-group", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_group/1)}
  end

  def handle_event("restore-group", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.restore_group/1)}
  end

  def handle_event("set-group-part", %{"part_number" => number}, socket) do
    {:noreply, edit(socket, &Draft.Edit.set_group_part(&1, to_int(number)))}
  end

  def handle_event("set-group-total", %{"parts_total" => total}, socket) do
    {:noreply, edit(socket, &Draft.Edit.set_group_total(&1, to_int(total)))}
  end

  def handle_event("approve-group", params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_group(&1, params["approved"] == "true"))}
  end

  def handle_event("link-group", params, socket) do
    id = to_int(params["recording_group_id"])

    {:noreply,
     edit(socket, fn draft ->
       if id do
         # Carry the linked group's set-level facts onto the link so the row
         # can display them — they're the group's, not the draft's, and are
         # ignored at import for a :link.
         group = Media.get_recording_group!(id)
         Draft.Edit.link_group(draft, id, %{name: group.name, parts_total: group.parts_total})
       else
         # Only when the form actually posted one: switching a link to a new
         # set posts no name, and blanking it would throw away what detection
         # got right.
         draft
         |> Draft.Edit.create_group()
         |> then(fn draft ->
           case params["name"] do
             nil -> draft
             name -> Draft.Edit.rename_group(draft, name)
           end
         end)
       end
     end)}
  end

  def handle_event("reset-group-name", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.reset_group_name/1)}
  end

  def handle_event("reset-credit-name", %{"section" => s, "index" => i}, socket) do
    item = socket.assigns.item

    {:noreply,
     edit(socket, fn draft ->
       draft
       |> Draft.Edit.reset_credit_name(atom(s), to_int(i))
       |> Draft.Edit.sync_people(item)
     end)}
  end

  def handle_event("reset-series-name", %{"index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.reset_series_name(&1, to_int(i)))}
  end

  # Separates the credited name from the human's, which is what puts a box on
  # their card. Offered from both the credit and the card, because either is
  # where the operator notices.
  def handle_event("separate-name", %{"section" => section, "index" => index}, socket) do
    {:noreply, edit(socket, &Draft.Edit.separate_person_name(&1, atom(section), to_int(index)))}
  end

  def handle_event("use-credited-name", %{"key" => key}, socket) do
    {:noreply, edit(socket, &Draft.Edit.use_credited_name(&1, key))}
  end

  # Reusing a human the library already has is the outcome worth having, and
  # the row that offers it is the only thing on the card that creates nothing.
  def handle_event("link-person", %{"key" => key, "id" => id}, socket) do
    {:noreply, edit(socket, &Draft.Edit.link_person(&1, key, to_int(id)))}
  end

  def handle_event("unlink-person", %{"key" => key}, socket) do
    {:noreply, edit(socket, &Draft.Edit.create_person(&1, key))}
  end

  # The escape hatch for when the name has moved since and nobody has
  # searched for who this now is. Writes evidence into `matches` like every
  # other re-search, not into page assigns.
  def handle_event("find-person", %{"key" => key}, socket) do
    item = socket.assigns.item
    name = person_name(item.draft, key)

    {:noreply,
     socket
     |> update(:searching_people, &Map.put(&1, key, name))
     |> start_async({:person_search, key}, fn -> Inbox.research_person(item, key, name) end)}
  end

  # A dozen headshots is normal for a working actor and would push the rest of
  # the credit off screen. View state, so it stays out of the draft.
  def handle_event("toggle-photos", %{"key" => key}, socket) do
    {:noreply, update(socket, :photos_expanded, &Map.update(&1, key, true, fn was -> !was end))}
  end

  def handle_event("pick-person-image", %{"key" => key} = params, socket) do
    {:noreply, edit(socket, &Draft.Edit.choose_person_image(&1, key, params["candidate"]))}
  end

  def handle_event("pick-person-bio", %{"key" => key} = params, socket) do
    {:noreply, edit(socket, &Draft.Edit.choose_person_bio(&1, key, params["candidate"]))}
  end

  def handle_event("waive-person-field", %{"key" => key, "field" => field}, socket) do
    {:noreply, edit(socket, &Draft.Edit.waive_person_field(&1, key, atom(field)))}
  end

  # A person's description is a description like any other: an imported blurb
  # is a starting point.
  def handle_event("person-bio", %{"key" => key} = params, socket) do
    {:noreply, edit(socket, &Draft.Edit.edit_person_bio(&1, key, params["description"]))}
  end

  def handle_event("split-person", %{"section" => s, "index" => i, "person" => p}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.split_person(&1, item, atom(s), to_int(i), to_int(p)))}
  end

  def handle_event("add-person", %{"section" => section, "index" => i}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.add_person(&1, item, atom(section), to_int(i)))}
  end

  def handle_event("remove-person", %{"section" => s, "index" => i, "person" => p}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.remove_person(&1, item, atom(s), to_int(i), to_int(p)))}
  end

  def handle_event("person-change", %{"key" => key} = params, socket) do
    # An existing person is chosen by id; anything else is a name to create.
    {:noreply,
     edit(socket, fn draft ->
       case to_int(params["person_id"]) do
         nil ->
           draft
           |> Draft.Edit.create_person(key)
           |> Draft.Edit.rename_person(key, params["name"] || "")

         id ->
           Draft.Edit.link_person(draft, key, id)
       end
     end)}
  end

  # "None of these" at the person level. A human no database has heard of is
  # a normal outcome, so this settles the level and creates them from their
  # name alone.
  def handle_event("uncatalogued-person", %{"key" => key}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.uncatalogued_person(&1, item, key))}
  end

  def handle_event("approve-person", %{"key" => key} = params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_person(&1, key, params["approved"] == "true"))}
  end

  # The person level's record checkboxes — the same evidence rule the work
  # and recording levels have, one paradigm across all three.
  def handle_event("toggle-person-source", %{"key" => key} = params, socket) do
    item = socket.assigns.item

    record =
      Enum.find(
        get_in(item.matches, ["people", key, "candidates"]) || [],
        &(&1["source"] == params["source"] and to_string(&1["id"]) == to_string(params["id"]))
      )

    if record do
      {:noreply, edit(socket, &Draft.Edit.toggle_person_source(&1, item, key, record))}
    else
      {:noreply, socket}
    end
  end

  # The person level's search-again form — the work-level pattern, with a
  # name instead of title/author fields. A blank name falls back to what the
  # draft currently calls them.
  def handle_event("research-person", %{"key" => key} = params, socket) do
    item = socket.assigns.item
    typed = params["name"] |> to_string() |> String.trim()
    name = if typed == "", do: person_name(item.draft, key), else: typed

    {:noreply,
     socket
     |> update(:searching_people, &Map.put(&1, key, name))
     |> start_async({:person_search, key}, fn -> Inbox.research_person(item, key, name) end)}
  end

  def handle_event("approve-credit", %{"section" => s, "index" => i} = params, socket) do
    {:noreply,
     edit(
       socket,
       &Draft.Edit.approve_credit(&1, atom(s), to_int(i), params["approved"] == "true")
     )}
  end

  def handle_event("remove-credit", %{"section" => s, "index" => i}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.remove_credit(&1, item, atom(s), to_int(i)))}
  end

  def handle_event("restore-credit", %{"section" => s, "index" => i}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.restore_credit(&1, item, atom(s), to_int(i)))}
  end

  def handle_event("set-series-number", %{"index" => i, "number" => number}, socket) do
    {:noreply, edit(socket, &Draft.Edit.set_series_number(&1, to_int(i), number))}
  end

  def handle_event("approve-series", %{"index" => i} = params, socket) do
    {:noreply,
     edit(socket, &Draft.Edit.approve_series(&1, to_int(i), params["approved"] == "true"))}
  end

  def handle_event("link-series", %{"index" => i} = params, socket) do
    index = to_int(i)
    id = to_int(params["series_id"])

    {:noreply,
     edit(socket, fn draft ->
       if id do
         Draft.Edit.link_series(draft, index, id)
       else
         draft
         |> Draft.Edit.create_series(index)
         |> Draft.Edit.rename_series(index, params["name"] || "")
       end
     end)}
  end

  def handle_event("remove-series", %{"index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_series(&1, to_int(i)))}
  end

  def handle_event("restore-series", %{"index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.restore_series(&1, to_int(i)))}
  end

  def handle_event("approve-work", params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_work(&1, params["approved"] == "true"))}
  end

  # Re-defaulted after each pick, because the policy is a fact about the
  # pairing.
  def handle_event("choose-root", %{"root_id" => root_id}, socket) do
    item = socket.assigns.item
    id = to_int(root_id)

    {:noreply,
     edit(socket, fn draft ->
       update_in(draft.destination, &(&1 |> Destination.choose_root(id) |> Seed.redefault(item)))
     end)}
  end

  def handle_event("choose-policy", %{"policy" => policy}, socket) do
    item = socket.assigns.item
    policy = to_policy(policy)

    {:noreply,
     edit(socket, fn draft ->
       update_in(
         draft.destination,
         &(&1 |> Destination.choose_policy(policy) |> Seed.redefault(item))
       )
     end)}
  end

  def handle_event("choose-start-unlisted", %{"start_unlisted" => value}, socket) do
    {:noreply,
     edit(socket, fn draft ->
       update_in(draft.recording, &%{&1 | start_unlisted: value == "true"})
     end)}
  end

  def handle_event("rebuild", _params, socket) do
    {:ok, item} = Inbox.rebuild_draft(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Started over from what the files and providers say.")
     |> load(item)}
  end

  # Queued rather than run here: an async task dies with the LiveView, so
  # closing the tab would kill the import mid-copy.
  #
  # `@collisions` carries the pre-flight, and passing it back says "yes, those
  # ones". A first click sends the empty list; a second sends what was just
  # read, so a library that moved in between stops them again.
  def handle_event("import", _params, socket) do
    case Inbox.import_item_async(socket.assigns.item, acknowledged: socket.assigns.collisions) do
      {:ok, job} ->
        message =
          cond do
            job.conflict? -> "Already working on this one."
            socket.assigns.replacing -> "Replacing the files. The row will say when it's done."
            true -> "Adding to the library. The row will say when it's done."
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, {:collisions, findings}} ->
        {:noreply, assign(socket, collisions: findings)}

      {:error, :already_imported} ->
        {:noreply, put_flash(socket, :error, Inbox.describe_error(:already_imported))}
    end
  end

  def handle_event("ignore", _params, socket) do
    {:ok, _item} = Inbox.ignore_item(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Ignored. Files untouched.")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  @impl Phoenix.LiveView

  # Only this person's search is over. `item` is the row as re-read and
  # merged under `Lookup`'s lock, so it carries whatever a search that
  # finished a moment ago wrote as well.
  def handle_async({:person_search, key}, {:ok, {:ok, item}}, socket) do
    {:noreply,
     socket
     |> update(:searching_people, &Map.delete(&1, key))
     |> load(item)
     |> resettle()}
  end

  # A provider being down costs its results and nothing else — the person is
  # still perfectly importable without a face.
  def handle_async({:person_search, key}, _failed, socket) do
    {:noreply, update(socket, :searching_people, &Map.delete(&1, key))}
  end

  def handle_async({:research, _level}, {:ok, {:ok, item}}, socket) do
    {:noreply,
     socket |> assign(researching: nil, research_fields: %{}) |> load(item) |> resettle()}
  end

  def handle_async({:retry, _level}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(retrying: nil) |> load(item) |> resettle()}
  end

  def handle_async({:enrich, _ref}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(enriching: nil) |> load(item) |> resettle()}
  end

  def handle_async(:chapter_titles, {:ok, fetched}, socket) do
    {:noreply, update_pending_import(socket, &AsyncResult.ok(&1, fetched))}
  end

  def handle_async(:chapter_titles, {:exit, reason}, socket) do
    {:noreply, update_pending_import(socket, &AsyncResult.failed(&1, async_fail(reason)))}
  end

  # A provider being unreachable is a thing to report, not to crash on: the
  # rest of the form is still usable.
  def handle_async(_name, result, socket) do
    Logger.warning(fn -> "Inbox form lookup failed: #{inspect(result)}" end)

    {:noreply,
     socket
     |> assign(researching: nil, retrying: nil, enriching: nil)
     |> assign(research_fields: %{}, searching_people: %{})
     |> put_flash(:error, "That provider couldn't be reached just now.")}
  end

  # New evidence has arrived; the ticked records may now say more than they
  # did. Re-deriving is what turns a freshly hydrated record into chips.
  defp resettle(socket) do
    item = socket.assigns.item

    case Inbox.update_draft_with(item, &Draft.Edit.resettle/2) do
      {:ok, item} -> load(socket, item)
      {:error, _reason} -> socket
    end
  end

  # Ticking a thin record is when its details start to matter, and ticking a
  # work record is when its editions do. Both are provider calls, so they run
  # off the render.
  defp enrich(socket, level, record) do
    item = socket.assigns.item
    ref = Inbox.record_ref(record)

    cond do
      not Draft.Edit.uses?(item.draft, atom(level), record) ->
        # un-ticking: nothing to fetch
        socket

      record["hydrated"] && level != "work" ->
        socket

      true ->
        socket
        |> assign(enriching: ref)
        |> start_async({:enrich, ref}, fn -> fetch(item, level, ref, record) end)
    end
  end

  defp fetch(item, level, ref, record) do
    with {:ok, item} <- hydrate_if_thin(item, level, ref, record) do
      if level == "work", do: Inbox.fetch_editions(item, [ref]), else: {:ok, item}
    end
  end

  defp hydrate_if_thin(item, _level, _ref, %{"hydrated" => true}), do: {:ok, item}
  defp hydrate_if_thin(item, level, ref, _record), do: Inbox.hydrate_record(item, level, ref)

  # Applied to the draft the row holds, not the one this socket shows: a form
  # can sit open while background work moves the row under it.
  defp edit(socket, fun) do
    case Inbox.update_draft_with(socket.assigns.item, fn draft, _item -> fun.(draft) end) do
      {:ok, item} ->
        load(socket, item)

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        assign(socket, form: to_form(changeset))

      {:error, _reason} ->
        socket
    end
  end

  defp load(socket, item) do
    job = Inbox.job_status(item)
    destination = Inbox.destination_preflight(item)
    replaces = replaces(item.draft)
    replacing = Replacement.replacing?(item.draft && item.draft.replacement)

    assign(socket,
      item: item,
      read_only: item.status == :imported,
      form: to_form(Inbox.change_draft(item)),
      unresolved: Draft.unresolved(item.draft),
      progress: Draft.progress(item.draft),
      # Whether this import is about an audiobook the library already has,
      # which is what decides whether the rest of the form is a question at
      # all.
      replacing: replacing,
      # The operator's choice, the path evidence's proposal, or the one they
      # declined: the same answer at three degrees of confidence.
      replaces: replaces,
      replacement_blocker: replacement_blocker(replacing, replaces),
      # Why the button is off when every decision is settled: facts about the
      # world rather than the draft, so not outstanding decisions.
      blocker:
        missing_blocker(item) || destination.blocker ||
          replacement_blocker(replacing, replaces),
      # What each level's search box starts from, resolved once per load: the
      # hints are parsed out of the release text.
      search_seeds: search_seeds(item),
      # Where each person is credited, so a row can say "same person as the
      # author". Derived, never stored.
      appearances: Draft.appearances(item.draft),
      destination: destination,
      # Which ways of dividing this item would actually divide it, for the
      # split controls. A part-set folder has both grains; a folder of three
      # files has only the finer one.
      grains: Inbox.split_grains(item),
      # The other half of that question, for when the walk went wrong the
      # other way: the items waiting under the same folder as this one, which
      # may be the parts of one audiobook.
      combine: Inbox.combine_group(item),
      # Matching retries with a backoff measured in minutes, so an item can be
      # legitimately mid-work while the form looks like nothing was found.
      job: job,
      # a job is going to change this draft, so the form is not editable yet
      busy: Inbox.busy?(job),
      # Roots are configuration and can change between seeding a draft and
      # approving it, so they're read now rather than frozen into the draft.
      roots: Ambry.Library.list_roots(),
      # What the pre-flight found when Add was last pressed. Cleared on
      # purpose: any change to the draft changes what it would create.
      collisions: []
    )
    |> schedule_tick()
  end

  @doc """
  What the button does, which changes once the pre-flight has spoken.

  After a collision what pressing it does is override an objection, and a
  button that still said "Add to the library" would hide that.
  """
  def import_words(true, _collisions), do: "Replace the files"
  def import_words(false, []), do: "Add to the library"
  def import_words(false, _collisions), do: "Add it anyway"

  @doc """
  Where a pre-flight match lives, so the operator can go and look at it.

  `Ambry.Inbox.Preflight` names the record and leaves the route alone. An
  author or narrator is edited on the person behind them.
  """
  def collision_path({:book, id}), do: ~p"/admin/books/#{id}/edit"
  def collision_path({:series, id}), do: ~p"/admin/series/#{id}/edit"
  def collision_path({:set, id}), do: ~p"/admin/sets/#{id}/edit"
  def collision_path({:person, id}), do: ~p"/admin/people/#{id}/edit"
  def collision_path(nil), do: nil

  defp atom("folder"), do: :folder
  defp atom("file"), do: :file
  defp atom("work"), do: :work
  defp atom("recording"), do: :recording
  defp atom("title"), do: :title
  defp atom("published"), do: :published
  defp atom("publisher"), do: :publisher
  defp atom("description"), do: :description
  defp atom("cover"), do: :cover

  defp direction("up"), do: :up
  defp direction(_down), do: :down

  @doc """
  The book this import links, if it links one.

  A set is reachable only through its book, so the set picker offers
  something exactly when the work links a library book.
  """
  def linked_book_id(%Draft{work: %Work{mode: :link, book_id: book_id}}), do: book_id
  def linked_book_id(_draft), do: nil

  defp group_absent?(%Draft{recording: %Recording{recording_group: nil}}), do: true
  defp group_absent?(%Draft{}), do: false

  defp to_int(nil), do: nil
  defp to_int(""), do: nil
  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  @placement_policies Placement.policies()

  defp to_policy(value) do
    Enum.find(@placement_policies, &(to_string(&1) == value))
  end

  # Named, not explained: a parenthetical about what each door costs is read
  # once and re-read on every import forever.
  defp placement_policies do
    Enum.map(Placement.policies(), &{Phoenix.Naming.humanize(&1), &1})
  end

  ## rendering helpers

  @doc """
  What a background job is doing to this item, if anything.

  The form is where somebody looks when a match seems wrong, and "still
  working" is a different answer from "nothing was found" — a rate-limited
  provider means minutes of backoff.
  """
  def job_label(:working), do: {"Still matching…", :blue}
  def job_label(:retrying), do: {"A provider couldn't be reached, retrying", :yellow}
  def job_label(:queued), do: {"Queued for matching", :blue}
  def job_label(:failed), do: {"Matching gave up. Try Start over.", :red}
  def job_label(:never_ran), do: {"The files were never read", :red}
  def job_label(:incomplete), do: {"Never finished matching", :yellow}
  def job_label(_settled), do: nil

  @doc """
  Whether the file list below already states where this item is.

  On most items the header's path and the list's common directory are the
  same string two cards apart, so the header drops its line.

  It stays when the files sit deeper than the item does, where which of the
  two this item is is what a split or a combine is about, and when there are
  no files at all.
  """
  def stated_by_files?(%InboxItem{files: []}), do: false

  def stated_by_files?(%InboxItem{path: path, files: files}) do
    case common_dir(files) do
      ^path -> true
      parent -> files == [path] and parent == folder_of(path)
    end
  end

  # `Path.dirname` says "." for a name with no directory in it; `common_dir`
  # says "" for the same thing, because it is about to print the answer.
  defp folder_of(path) do
    case Path.dirname(path) do
      "." -> ""
      dir -> dir
    end
  end

  @doc "What the item's files say they are, for the evidence header."
  def evidence(%InboxItem{probe: probe}) when is_map(probe),
    do: probe |> probe_facts(files: true) |> Enum.join(" · ")

  def evidence(_item), do: "not read yet"

  @doc """
  The fallback line for an item whose draft has no chapters decision yet —
  the probe hasn't read the files, or the draft predates it (stale, and the
  banner already says so). The editor itself renders from the draft.
  """
  def chapter_summary(%InboxItem{probe: %{"chapters" => count}}) when count > 0,
    do: "#{count} chapters in the files. Start over to stage them here."

  def chapter_summary(%InboxItem{probe: probe}) when is_map(probe),
    do: "No chapters in the files. The audiobook will have none until they're added."

  def chapter_summary(_item), do: "Not read yet."

  # The draft's staged chapter rows — what the chapters editor shows, what a
  # merge aligns against, and (autosaved) always what is on screen.
  defp draft_chapter_rows(%InboxItem{draft: %{recording: %{chapters: %{chapters: rows}}}}),
    do: rows

  defp draft_chapter_rows(_item), do: []

  # A change from the chapters form is the operator touching the rows: typed
  # titles stop claiming a source a merge could overwrite.
  defp curate_chapter_params(params, item) do
    case get_in(params, ["draft", "recording", "chapters"]) do
      nil ->
        params

      chapter_params ->
        put_in(
          params,
          ["draft", "recording", "chapters"],
          chapter_params
          |> mark_typed_titles(draft_chapter_rows(item))
          |> Map.put("curated", "true")
        )
    end
  end

  @doc """
  The files' own list as a proposal chip, or nil when they carry none.

  Chosen when the staged rows still match what the probe read, so the chip
  reports as well as offers. Files with no chapters propose nothing, or the
  chip would be a destructive control wearing a proposal's clothes.
  """
  def file_chapter_chip(item) do
    case Seed.file_chapters(item) do
      %Chapters{chapters: [_row | _rest] = rows} ->
        %{chosen: same_chapters?(draft_chapter_rows(item), rows)}

      _no_file_chapters ->
        nil
    end
  end

  # Compared on what the operator can see and change: two identical lists
  # that disagree about `title_source` are still the same list.
  defp same_chapters?(staged, from_files) when length(staged) == length(from_files) do
    staged
    |> Enum.zip(from_files)
    |> Enum.all?(fn {row, file_row} ->
      row.title == file_row.title and same_time?(row.time, file_row.time)
    end)
  end

  defp same_chapters?(_staged, _from_files), do: false

  defp same_time?(%Decimal{} = staged, %Decimal{} = from_file),
    do: Decimal.equal?(staged, from_file)

  defp same_time?(staged, from_file), do: staged == from_file

  # One chip per distinct ASIN among the ticked recording records — the
  # evidence panel is the search, so the chips are wherever its ticks are.
  defp chapter_chips(item, applied_asin) do
    case item.draft && item.draft.recording do
      %Recording{} = recording ->
        item
        |> Seed.records("recording")
        |> Enum.filter(&Recording.uses?(recording, &1))
        |> title_chips(applied_asin)

      _no_draft ->
        []
    end
  end

  @doc """
  What the files themselves said, before anybody interpreted it.

  The tags are the primary source, carried by nearly every release, so when a
  match goes somewhere strange this is where the cause is and the form has to
  show it.
  """
  def tag_rows(%InboxItem{tags: tags}) when is_map(tags) do
    for key <- ~w(book_title authors narrators series series_number published publisher asin),
        value = tags[key],
        value not in [nil, "", []] do
      {tag_label(key), format_tag(value)}
    end
  end

  def tag_rows(_item), do: []

  defp tag_label("book_title"), do: "title"
  defp tag_label("series_number"), do: "series no."
  defp tag_label(key), do: String.replace(key, "_", " ")

  defp format_tag(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_tag(value), do: to_string(value)

  attr :files, :list, required: true

  @doc """
  The search terms auto-match derived, and where each came from.

  Tags win over the release name because they're measurably more reliable, but
  that means a wrong tag beats a right folder name — worth being able to see.
  """
  def hint_rows(%InboxItem{matches: %{"hints" => hints}}) when is_map(hints) do
    for key <- ~w(title author narrator series asin),
        value = hints[key],
        value not in [nil, ""],
        do: {key, value}
  end

  def hint_rows(_item), do: []

  @doc """
  Why nothing was filled in from a recording match.

  "No provider listed this" and "a provider listed a different reader's
  edition" want completely different things from the operator, and an empty
  set of fields says neither.
  """
  def doubt_message(%Work{doubt: :low_confidence, doubt_detail: detail}), do: detail

  def doubt_message(%Work{}), do: nil

  def doubt_message(%Recording{doubt: :narrator_conflict, doubt_detail: detail}), do: detail

  def doubt_message(%Recording{doubt: :low_confidence, doubt_detail: detail}), do: detail

  def doubt_message(%Recording{doubt: :nothing_found}),
    do:
      "No provider had a record of this audiobook. The fields below come from the file's own tags."

  def doubt_message(_recording), do: nil

  @doc """
  Which providers were asked at this level, and what each said.

  A provider that errors contributes nothing, so without a trace of it a
  rate-limited or misconfigured source looks exactly like one that genuinely
  had no answer, and the operator's only clue is a shorter list than they
  expected.
  """
  def provider_outcomes(%InboxItem{matches: matches}, level) when is_map(matches) do
    get_in(matches, [level, "providers"]) || []
  end

  def provider_outcomes(_item, _level), do: []

  defp replaces(%Draft{replacement: %Replacement{media_id: id}}) when is_integer(id),
    do: Media.media_option(id)

  defp replaces(_no_proposal), do: nil

  # A recording can be deleted between being chosen and the button being
  # pressed. Not an unresolved *decision*: the operator answered, and the
  # answer stopped being true.
  #
  # Missing files make every other answer moot, and are the same kind of fact,
  # about the world rather than the draft.
  #
  # Only where something is still being decided. An imported item is not
  # importing, and for a `move` placement its source is gone *because the
  # import took it*.
  @doc """
  Whether this item's files have gone away since it was found.
  """
  def missing?(%{missing_since: at}), do: not is_nil(at)

  defp missing_blocker(%{status: :imported}), do: nil
  defp missing_blocker(%{missing_since: nil}), do: nil
  defp missing_blocker(%{}), do: Inbox.describe_error(:files_missing)

  defp replacement_blocker(true, nil),
    do:
      "The audiobook this was going to replace has been deleted. " <>
        "Choose another, or say this is a new audiobook."

  defp replacement_blocker(_replacing, _replaces), do: nil

  @doc """
  Whether replacing this recording's files would destroy the only copy.

  Read at render rather than stored, because it is a fact about the disk
  right now: a library copy hardlinked from a torrent that has since been
  removed is down to one name, and the draft was written before that could
  happen. See `Ambry.Media.only_copy?/1` for why the link count is the
  test and not the policy the import remembered.
  """
  def only_copy?(nil), do: false
  def only_copy?(%{id: id}), do: Media.only_copy?(id)

  @doc "How a provider record is referred to."
  defdelegate record_ref(record), to: Inbox

  @doc "The provider records found for a level."
  defdelegate records(item, level), to: Seed

  @doc "Existing Books this release might be another edition of."
  defdelegate local_records(item, level), to: Seed
end
