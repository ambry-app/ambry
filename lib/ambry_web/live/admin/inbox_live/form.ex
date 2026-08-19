defmodule AmbryWeb.Admin.InboxLive.Form do
  @moduledoc """
  The staged import form: everything this release will become, before any of
  it is real.

  Built on one invariant — **an import is a tree of decisions, and import is
  possible iff every decision is resolved**. The button at the bottom reads
  `Draft.unresolved/1` and nothing else, which is what guarantees the form
  never offers an action that fails: everything that could go wrong at
  import was a visible decision before the button was pressed.

  ## Two kinds of interaction, deliberately

  Typing is ordinary form input, autosaved on change — so there is never an
  unsaved edit to lose when something else is clicked. Choosing (which
  candidate, which identity, who's behind a credit) is a named event that
  transforms the stored draft through `Draft.Edit`, because those aren't text
  and pretending they are is where hidden-input tricks come from.

  ## Vocabulary

  A credit reads as one line — "Written by" / "Read by" — and the humans
  behind it live in their own section, one card each. An earlier version
  showed both levels inside every credit, on the theory that "Credited as /
  Written by" teaches the model for free; in practice it charged every
  ordinary import for a question about personhood that only two imports in a
  hundred have an interesting answer to, and printed a person twice whenever
  an author read their own book.

  What is left of that question on the credit is "This is a pen name" /
  "This is a stage name": the credited name is not the human's name. It gives
  that human a name of their own and takes the operator to the card where the
  box for it has just appeared.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.ChapterEditor
  import AmbryWeb.Admin.Decisions
  import AmbryWeb.TimeUtils

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
  alias AmbryWeb.Admin.ReturnTo
  alias AmbryWeb.Components.EntityResolver
  alias Phoenix.LiveView.AsyncResult

  require Logger

  @impl Phoenix.LiveView
  def mount(%{"id" => id} = params, _session, socket) do
    item = Inbox.get_item!(id)
    {:ok, item} = Inbox.prepare_draft(item)

    {:ok,
     socket
     |> assign(page_title: InboxItem.name(item))
     |> assign(researching: nil, retrying: nil, enriching: nil)
     # What the in-flight search asked for. The stored query only updates
     # when results land, so a form that renders storage describes the
     # PREVIOUS search for the whole round trip — the typed words vanish from
     # the boxes at the click and the scrim names the wrong book. The edit
     # forms have always captured this (`Evidence.begin/2`); this is the same
     # discipline for the staged form.
     |> assign(research_fields: %{}, searching_person_name: nil)
     # Which person is being looked up again, and whose photo strip is showing
     # in full. Both view state keyed by person key — the results themselves
     # are evidence and live on the item.
     |> assign(searching_person: nil, photos_expanded: %{})
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
  # whitelist is `ReturnTo`'s now, which is how this stopped dropping
  # `problem`: a form opened from a queue narrowed to "Files couldn't be read"
  # used to return to the whole queue.
  defp return_to(params), do: ReturnTo.path(~p"/admin/inbox", ReturnTo.list_params(params))

  # An imported item's draft is the record of what was imported — the operator
  # already created the library records from it, and an edit here would make
  # the record lie. The banner and `inert` explain; this enforces, because
  # markup is advisory and a stale tab can still send anything. The only
  # events allowed through are pure view state.
  @view_events ~w(toggle-photos)

  defp refuse_when_imported(event, _params, socket) do
    if socket.assigns.read_only and event not in @view_events do
      {:halt, put_flash(socket, :error, Inbox.describe_error(:already_imported))}
    else
      {:cont, socket}
    end
  end

  # **The overlay explains; this enforces.** `inert` and a scrim are markup,
  # and markup is advisory — a stale tab, a keyboard, or a reconnect can all
  # still send an event. Matching rebuilds an untouched draft when a retried
  # provider finally answers, so an edit accepted here would be thrown away by
  # work the operator couldn't see.
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

  One predicate for both, because the form's answer is the same either way:
  the overlay, the `inert`, and the refusal are about "not yours to edit",
  not about who took it.
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
  # Naming the slow part, because it is the part that makes the operator
  # wonder whether the click landed: a multi-file release is re-probed file
  # by file and then every one of them is placed.
  def busy_label(:importing), do: "Adding to the library…"
  def busy_label(:working), do: "Matching…"
  def busy_label(:retrying), do: "A provider couldn't be reached. Retrying…"
  def busy_label(:queued), do: "Queued for matching…"
  def busy_label(_idle), do: "Working…"

  @doc """
  What a level's search box shows: the query in flight while one is running,
  and the last one asked otherwise.

  The stored query is only written when results land, so rendering it during
  the round trip describes the *previous* search — which is why typed words
  appeared to revert the moment Search was pressed and the scrim named the
  wrong book. The edit forms never had this because `Evidence.begin/2`
  records the submitted fields at the click; this is the same rule for a
  form whose query lives in the database instead of a struct.
  """
  def search_fields(level, level, in_flight, _seeded), do: in_flight
  def search_fields(_researching, _level, _in_flight, seeded), do: seeded

  # The query keys a search form can submit — the same set
  # `Provider.Query.from_fields/1` reads, so what comes back is exactly what
  # was asked for.
  @query_keys ~w(title author narrator)

  defp submitted_fields(params), do: Map.take(params, @query_keys)

  # What each level's boxes hold when no search is in flight.
  #
  # The stored query is what was last *asked*, and for a recording matched by
  # its ASIN that is `%{"keywords" => "B0…"}` — a shape this form has no box
  # for. So the audiobook card rendered three empty boxes above a button
  # that submitted a blank query, which `Lookup.research/3` correctly treats
  # as nothing to do: a dead control that said nothing about why. Falling
  # back to the hints matching itself used means a box always holds
  # something submittable, the way the edit forms seed their panel from the
  # record they belong to.
  #
  # Wholesale, never per key: merging hints into a stored query would put
  # back an author the operator deliberately cleared, which is the bug this
  # whole pass is about.
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

  Named rather than a bare "Searching…", because the operator has just typed
  the words into the box above it and seeing them come back is what says the
  click landed on the search they meant.
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
  The people the library already has by this human's name.

  Collected by matching whenever a credited name is already in the library —
  the author who turns up narrating, whose name the credit's typeahead cannot
  offer because the identity they need doesn't exist yet. Without a route to
  them the form's only answer was a second Person of the same name.
  """
  def person_locals(item, key), do: get_in(item.matches, ["people", key, "local"]) || []

  @doc """
  The name this person's records were searched for.

  The person level's `query_fields`: seeded by matching with the credited
  name and rewritten by every re-search, so the search box can hold the query
  rather than the person's name decision — which is a different answer and
  was snapping the box back the moment results arrived.

  In flight it is the name just submitted, for the same reason
  `search_fields/3` is: until the results land, storage still describes the
  previous search.
  """
  def person_query_name(_item, key, key, name) when is_binary(name), do: name

  def person_query_name(item, key, _searching_key, _searching_name),
    do: get_in(item.matches, ["people", key, "name"])

  @impl Phoenix.LiveView
  def handle_event("validate", %{"inbox_item" => params}, socket) do
    params = curate_chapter_params(params, socket.assigns.item)

    # Autosave: the form and the stored draft are never allowed to disagree,
    # so a click on any of the choice controls below can't discard typing.
    case Inbox.update_draft(socket.assigns.item, params["draft"] || %{}) do
      {:ok, item} -> {:noreply, load(socket, item)}
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
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
  # something the library already has, so nothing below is in question.
  #
  # A blank id is the surrounding form reporting itself for some other reason,
  # not an answer — the way back from a replacement is the chip beside the
  # box, the same as at the work level. (`EntityResolver` only reports a pure
  # picker's value when something is picked, so this is belt and braces.)
  def handle_event("replace-recording", %{"id" => id}, socket) do
    case to_int(id) do
      nil -> {:noreply, socket}
      media_id -> {:noreply, edit(socket, &Draft.Edit.replace_recording(&1, media_id))}
    end
  end

  def handle_event("new-recording", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.new_recording/1)}
  end

  def handle_event("link-book", %{"id" => id}, socket) do
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

        # A record nobody had asked about is a summary. Ticking it is the
        # moment its description and cover start to matter, so that's when
        # they're fetched — and when it's a work record, when its editions
        # become worth asking for.
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
  # The same event vocabulary as the media form: the fetched titles render
  # into the rows as a proposed column, and Take applies them through
  # `Draft.Edit.set_chapters/2` so the answer survives reseeds.

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

  # The way back to the machine's value, which every other decision has and
  # this one didn't: re-derive the rows from the probe and record that the
  # operator chose them. Taking a value the rows already hold still counts as
  # reviewing it — that is the whole point of the tier, and why agreeing with
  # the files must not require editing them first.
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
         # Rename only when the form actually posted one. Switching a link to
         # a new set posts no name — the name box is not on the page yet —
         # and blanking the set's name because a drop-down moved would throw
         # away the one thing detection got right.
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

  # The credited name is not always the human's name — "David Wong" is Jason
  # Pargin — so this separates the two: the person gets a name of their own,
  # which is what puts a box on their card. It is offered from both ends, the
  # credit and the card, because either is where the operator notices.
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

  # The photos and bios matching already found are in the person's own fields,
  # so there is nothing to fetch to show them. This is the escape hatch for
  # when the *name* has moved since — a rename, a pen name revealed, a person
  # split in two — where nobody has ever searched for who this now is.
  #
  # Writes evidence into `matches`, exactly as the work-level re-search does,
  # rather than into page assigns: results that vanish on reload were fine
  # when nothing else knew about people, and are now just a second place for
  # the same thing to live.
  def handle_event("find-person", %{"key" => key}, socket) do
    item = socket.assigns.item
    name = person_name(item.draft, key)

    {:noreply,
     socket
     |> assign(searching_person: key, searching_person_name: name)
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
  # is a starting point, and the recording's has been an editable box since
  # the form existed.
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
  # a normal outcome — plenty of narrators are in none — so this settles the
  # level and creates them from their name alone.
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
     |> assign(searching_person: key, searching_person_name: name)
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
  # pairing: changing the root changes what "how the files come in" should
  # propose, and an unpicked policy has no business keeping the answer that
  # belonged to the previous root.
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

  def handle_event("rebuild", _params, socket) do
    {:ok, item} = Inbox.rebuild_draft(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Started over from what the files and providers say.")
     |> load(item)}
  end

  # Queued and handed back to the queue. Importing re-probes every file and
  # then moves the bytes — measured on a 28-file release, seven seconds of
  # ffprobe plus a 131MB copy, and a copy off a NAS is slower still. Held in
  # an async task it pinned the operator to a spinner, and worse, the task
  # **died with the LiveView**: closing the tab killed the import mid-copy.
  #
  # Now the server owns it. The operator goes back to the list they came from
  # and the row wears the same busy overlay every other job gives it.
  # The pre-flight is what `@collisions` carries, and passing it back is what
  # says "yes, those ones". A first click sends the empty list, so anything
  # found stops it; a second sends what the operator just read, and if the
  # library moved in between the lists differ and it stops them again.
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

  def handle_async({:person_search, _key}, {:ok, {:ok, item}}, socket) do
    {:noreply,
     socket
     |> assign(searching_person: nil, searching_person_name: nil)
     |> load(item)
     |> resettle()}
  end

  # A provider being down costs its results and nothing else — the person is
  # still perfectly importable without a face.
  def handle_async({:person_search, _key}, _failed, socket) do
    {:noreply, assign(socket, searching_person: nil, searching_person_name: nil)}
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

  # A provider being unreachable at this moment is a thing to report, not a
  # thing to crash on — the operator is mid-edit and the rest of the form is
  # still perfectly usable.
  def handle_async(_name, result, socket) do
    Logger.warning(fn -> "Inbox form lookup failed: #{inspect(result)}" end)

    {:noreply,
     socket
     |> assign(researching: nil, retrying: nil, enriching: nil)
     |> assign(research_fields: %{}, searching_person: nil, searching_person_name: nil)
     |> put_flash(:error, "That provider couldn't be reached just now.")}
  end

  # New evidence has arrived; the ticked records may now say more than they
  # did. Re-deriving is what turns a freshly hydrated record into chips.
  defp resettle(socket) do
    item = socket.assigns.item

    case Inbox.update_draft(item, Inbox.dump_draft(Draft.Edit.resettle(item.draft, item))) do
      {:ok, item} -> load(socket, item)
      {:error, _changeset} -> socket
    end
  end

  # Ticking a thin record is the moment its details start to matter; ticking a
  # work record is the moment its editions do.
  # Ticking a thin record is the moment its details start to matter; ticking a
  # work record is the moment its editions do. Both are provider calls, so
  # they happen off the render and the row says it's working.
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

  defp edit(socket, fun) do
    draft = fun.(socket.assigns.item.draft)

    case Inbox.update_draft(socket.assigns.item, Inbox.dump_draft(draft)) do
      {:ok, item} -> load(socket, item)
      {:error, changeset} -> assign(socket, form: to_form(changeset))
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
      # The recording under that decision — the operator's choice, or the
      # proposal the path evidence made, or the one they declined. All three
      # render the same row: they are the same answer at different degrees of
      # confidence, and a declined proposal is how the way back stays open.
      replaces: replaces,
      replacement_blocker: replacement_blocker(replacing, replaces),
      # Why the button is off when every decision is settled. Both halves are
      # facts about the world rather than about the draft — a root that went
      # away, an audiobook that was deleted — so they're read here and not
      # counted as outstanding decisions.
      blocker: destination.blocker || replacement_blocker(replacing, replaces),
      # What each level's search box starts from, resolved once per load
      # rather than per render — the hints are parsed out of the release
      # text.
      search_seeds: search_seeds(item),
      # Where each person is credited, so a row can say "same person as the
      # author". Derived, never stored — one human is one record now, and a
      # second copy of "who is where" is what used to drift.
      appearances: Draft.appearances(item.draft),
      destination: destination,
      # Which ways of dividing this item would actually divide it, for the
      # split controls. Both grains exist on a GraphicAudio set; a folder of
      # three files has only the finer one.
      grains: Inbox.split_grains(item),
      # Matching retries with a backoff measured in minutes, so an item can be
      # legitimately mid-work while the form looks like nothing was found.
      job: job,
      # a job is going to change this draft, so the form is not editable yet
      busy: Inbox.busy?(job),
      # Roots are configuration and can change between seeding a draft and
      # approving it, so they're read now rather than frozen into the draft.
      roots: Ambry.Library.list_roots(),
      # What the pre-flight found when Add was last pressed. Cleared here on
      # purpose: any change to the draft is a change to what it would create,
      # so an answer given about the old one may not be an answer about this
      # one.
      collisions: []
    )
    |> schedule_tick()
  end

  @doc """
  What the button does, which changes once the pre-flight has spoken.

  Named for what pressing it does, same as it always was: after a collision
  the thing it does is override an objection, and a button that still said
  "Add to the library" would hide that pressing it again is the answer.
  """
  def import_words(true, _collisions), do: "Replace the files"
  def import_words(false, []), do: "Add to the library"
  def import_words(false, _collisions), do: "Add it anyway"

  @doc """
  Where a pre-flight match lives, so the operator can go and look at it.

  `Ambry.Inbox.Preflight` names the record and leaves the route alone: it
  runs nowhere near a web layer, and an author or a narrator is edited on
  the person behind them rather than on a page of their own.
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

  A set is reachable only through its book, so the set picker offers something
  exactly when the work links a library book — a `:create` work has no sets
  yet, and there the resolver is create-only.
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

  # Named, not explained. Each label used to carry a parenthetical about
  # what the door costs, which is a definition an operator reads once and
  # then re-reads on every import forever. The one consequence that still
  # needs saying is the one that stops an import, and it says itself when
  # the impossible door is picked.
  defp placement_policies do
    Enum.map(Placement.policies(), &{Phoenix.Naming.humanize(&1), &1})
  end

  ## rendering helpers

  @doc """
  What a background job is doing to this item, if anything.

  The form is where somebody looks when a match seems wrong, and "still
  working" is a completely different answer from "nothing was found" —
  especially now that a rate-limited provider means minutes of backoff rather
  than an immediate give-up.
  """
  def job_label(:working), do: {"Still matching…", :blue}
  def job_label(:retrying), do: {"A provider couldn't be reached, retrying", :yellow}
  def job_label(:queued), do: {"Queued for matching", :blue}
  def job_label(:failed), do: {"Matching gave up. Try Start over.", :red}
  def job_label(:never_ran), do: {"The files were never read", :red}
  def job_label(:incomplete), do: {"Never finished matching", :yellow}
  def job_label(_settled), do: nil

  @doc "What the item's files say they are, for the evidence header."
  def evidence(%InboxItem{probe: probe}) when is_map(probe) do
    [
      probe["duration"] && format_timecode(Decimal.new(probe["duration"])),
      file_count(probe),
      probe["codec"],
      probe["chapters"] && probe["chapters"] > 0 && "#{probe["chapters"]} chapters",
      probe["seek_accuracy"] == "approximate" && "inexact seeking"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  def evidence(_item), do: "not read yet"

  # A one-file recording says nothing; a forty-file one is the single most
  # useful fact about it, because it's what the timeline is built out of.
  defp file_count(%{"files" => count}) when count > 1, do: "#{count} files"
  defp file_count(_probe), do: nil

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

  # A change event from the chapters form is the operator touching the rows:
  # typed titles stop claiming the source that would let a merge overwrite
  # them, and the decision records its curation — which is what survives
  # reseeds.
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
  reports as well as offers. Files with no chapters propose nothing: a chip
  that emptied the rows an operator typed by hand would be a destructive
  control wearing a proposal's clothes.
  """
  def file_chapter_chip(item) do
    case Seed.file_chapters(item) do
      %Chapters{chapters: [_row | _rest] = rows} ->
        %{chosen: same_chapters?(draft_chapter_rows(item), rows)}

      _no_file_chapters ->
        nil
    end
  end

  # Compared on what the operator can see and change — a time and a title.
  # `title_source` is bookkeeping about where a title came from, and two
  # identical lists that disagree about it are still the same list.
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

  The tags are the primary source — 98% of the operator's real releases carry
  a usable one — so when a match goes somewhere strange this is where the
  cause is, and it was previously visible nowhere in the form.
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

  A provider that errors contributes nothing and used to leave no trace, so a
  rate-limited or misconfigured source looked exactly like one that genuinely
  had no answer — and the operator's only clue was a shorter list than they
  expected.
  """
  def provider_outcomes(%InboxItem{matches: matches}, level) when is_map(matches) do
    get_in(matches, [level, "providers"]) || []
  end

  def provider_outcomes(_item, _level), do: []

  defp replaces(%Draft{replacement: %Replacement{media_id: id}}) when is_integer(id),
    do: Media.media_option(id)

  defp replaces(_no_proposal), do: nil

  # A recording can be deleted between the moment it was chosen and the
  # moment the button is pressed, and the one thing this form may not do is
  # offer an action that fails. Not an unresolved *decision* — the operator
  # answered the question, and the answer stopped being true.
  defp replacement_blocker(true, nil),
    do:
      "The audiobook this was going to replace has been deleted. " <>
        "Choose another, or say this is a new audiobook."

  defp replacement_blocker(_replacing, _replaces), do: nil

  @doc """
  Whether replacing this recording's files would destroy the only copy.

  Read at render rather than stored, because it is a fact about the disk
  right now: a library copy hardlinked from a torrent that has since been
  removed is down to one name, and the draft was written before that
  happened. See `Ambry.Media.only_copy?/1` for why the link count is the
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
