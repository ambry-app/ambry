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

  A credit reads as one line — "Written by" / "Narrated by" — and the person
  layer is folded away behind "This is a pen name" / "This is a stage name".
  An earlier version showed both levels always, on the theory that "Credited
  as / Written by" teaches the model for free; in practice it charged every
  ordinary import for a question about personhood that only two imports in a
  hundred have an interesting answer to. The fold unfolds itself whenever the
  credit is anything but one new person of the same name, so nothing
  interesting can hide inside it.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Decisions
  import AmbryWeb.TimeUtils

  alias Ambry.Books
  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Credit
  alias Ambry.Inbox.Draft.Field
  alias Ambry.Inbox.Draft.Recording
  alias Ambry.Inbox.Draft.Seed
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.Media
  alias Ambry.People

  require Logger

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    item = Inbox.get_item!(id)
    {:ok, item} = Inbox.prepare_draft(item)

    {:ok,
     socket
     |> assign(page_title: InboxItem.name(item))
     |> assign(series: Books.series_for_select())
     |> assign(authors: People.authors_for_select(), narrators: People.narrators_for_select())
     |> assign(author_backing: People.author_backing_names())
     |> assign(narrator_backing: People.narrator_backing_names())
     |> assign(people: People.people_for_select())
     |> assign(expanded: MapSet.new())
     |> assign(researching: nil, retrying: nil, enriching: nil)
     # Which person is being looked up again, and whose photo strip is showing
     # in full. Both are view state keyed by person key — the results
     # themselves are evidence and live on the item.
     |> assign(searching_person: nil, photos_expanded: %{})
     |> assign(library_query: nil, library_results: [], ticking: false)
     |> attach_hook(:refuse_while_busy, :handle_event, &refuse_while_busy/3)
     |> attach_hook(:refuse_when_imported, :handle_event, &refuse_when_imported/3)
     |> load(item)}
  end

  # An imported item's draft is the record of what was imported — the operator
  # already created the library records from it, and an edit here would make
  # the record lie. The banner and `inert` explain; this enforces, because
  # markup is advisory and a stale tab can still send anything. The only
  # events allowed through are pure view state.
  @view_events ~w(toggle-photos toggle-people)

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
    if socket.assigns.busy do
      Logger.debug(fn -> "Inbox form: refusing #{event} while a job owns item" end)
      {:halt, socket}
    else
      {:cont, socket}
    end
  end

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
  def busy_label(:working), do: "Matching…"
  def busy_label(:retrying), do: "A provider couldn't be reached — waiting to try again…"
  def busy_label(:queued), do: "Queued for matching…"
  def busy_label(_idle), do: "Working…"

  @doc """
  Whether a credit's person layer should be showing.

  Folded away for the ordinary case — one new person of the same name — and
  unfolded whenever the credit is anything else, so a pen name can never be
  hiding behind a collapsed control.
  """
  def expanded?(expanded, section, index, credit) do
    MapSet.member?(expanded, {section, index}) or not Credit.simple?(credit)
  end

  # What a person is currently called, which is what a re-search asks about.
  defp person_name(draft, key) do
    case Draft.person(draft, key) do
      nil -> nil
      person -> Field.value(person.name)
    end
  end

  # The person level's records and provider outcomes, keyed by person, for
  # the same evidence rows the work and recording sections render.
  defp person_records(item) do
    for {key, matched} <- item.matches["people"] || %{}, into: %{} do
      {key, matched["candidates"] || []}
    end
  end

  defp person_outcomes(item) do
    for {key, matched} <- item.matches["people"] || %{}, into: %{} do
      {key, matched["providers"] || []}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"inbox_item" => params}, socket) do
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

  def handle_event("link-book", %{"id" => id}, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.link_book(&1, item, to_int(id)))}
  end

  # The escape hatch. Matching finds the ordinary case and cannot be expected
  # to find every one: a file tagged "HP1 - The Philosopher's Stone" and a book
  # called "Harry Potter and the Sorcerer's Stone" are the same work and no
  # string comparison should be asked to know that. Rather than chase it, give
  # the operator a way to go and look.
  def handle_event("search-library", %{"query" => query}, socket) do
    results =
      case Books.match_keywords(query) do
        [] -> []
        terms -> terms |> Books.match_books(10) |> Enum.map(&local_book/1)
      end

    {:noreply, assign(socket, library_query: query, library_results: results)}
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

  def handle_event("uncatalogued", _params, socket) do
    item = socket.assigns.item
    {:noreply, edit(socket, &Draft.Edit.uncatalogued(&1, item))}
  end

  def handle_event("research", %{"level" => level} = params, socket) do
    item = socket.assigns.item

    {:noreply,
     socket
     |> assign(researching: level)
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

  def handle_event("split", _params, socket) do
    case Inbox.split_item(socket.assigns.item) do
      {:ok, children} ->
        {:noreply,
         socket
         |> put_flash(:info, "Split into #{length(children)} items — scanning each fresh now.")
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
         draft
         |> Draft.Edit.create_group()
         |> Draft.Edit.rename_group(params["name"] || "")
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

  # Whether the person layer is unfolded is view state, not a decision — it
  # has no business in the stored draft.
  def handle_event("toggle-people", %{"section" => section, "index" => index}, socket) do
    {:noreply,
     update(socket, :expanded, fn expanded ->
       key = {section, to_int(index)}

       if MapSet.member?(expanded, key),
         do: MapSet.delete(expanded, key),
         else: MapSet.put(expanded, key)
     end)}
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
     |> assign(searching_person: key)
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
     |> assign(searching_person: key)
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

  def handle_event("confirm-level", %{"section" => s}, socket) do
    {:noreply, edit(socket, &Draft.Edit.confirm_level(&1, atom(s)))}
  end

  def handle_event("choose-root", %{"root_id" => root_id}, socket) do
    id = to_int(root_id)

    {:noreply,
     edit(socket, fn draft ->
       update_in(draft.destination, &%{&1 | root_id: id, approved: not is_nil(id)})
     end)}
  end

  def handle_event("rebuild", _params, socket) do
    {:ok, item} = Inbox.rebuild_draft(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Started over from what the files and providers say.")
     |> load(item)}
  end

  def handle_event("import", _params, socket) do
    case Inbox.import_item(socket.assigns.item) do
      {:ok, _media} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added to the library.")
         |> push_navigate(to: ~p"/admin/inbox")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Inbox.describe_error(reason))
         |> load(Inbox.get_item!(socket.assigns.item.id))}
    end
  end

  def handle_event("ignore", _params, socket) do
    {:ok, _item} = Inbox.ignore_item(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Ignored. Files untouched.")
     |> push_navigate(to: ~p"/admin/inbox")}
  end

  @impl Phoenix.LiveView
  def handle_async({:person_search, _key}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(searching_person: nil) |> load(item) |> resettle()}
  end

  # A provider being down costs its results and nothing else — the person is
  # still perfectly importable without a face.
  def handle_async({:person_search, _key}, _failed, socket) do
    {:noreply, assign(socket, searching_person: nil)}
  end

  def handle_async({:research, _level}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(researching: nil) |> load(item) |> resettle()}
  end

  def handle_async({:retry, _level}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(retrying: nil) |> load(item) |> resettle()}
  end

  def handle_async({:enrich, _ref}, {:ok, {:ok, item}}, socket) do
    {:noreply, socket |> assign(enriching: nil) |> load(item) |> resettle()}
  end

  # A provider being unreachable at this moment is a thing to report, not a
  # thing to crash on — the operator is mid-edit and the rest of the form is
  # still perfectly usable.
  def handle_async(_name, result, socket) do
    Logger.warning(fn -> "Inbox form lookup failed: #{inspect(result)}" end)

    {:noreply,
     socket
     |> assign(researching: nil, retrying: nil, enriching: nil)
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

    assign(socket,
      item: item,
      read_only: item.status == :imported,
      form: to_form(Inbox.change_draft(item)),
      unresolved: Draft.unresolved(item.draft),
      progress: Draft.progress(item.draft),
      # A recording group is reachable only through its book, so the picker
      # has options exactly when the work links a library book. A :create
      # work has no groups yet — the resolver is create-only there.
      group_options: group_options(item.draft),
      # Where each person is credited, so a row can say "same person as the
      # author". Derived, never stored — one human is one record now, and a
      # second copy of "who is where" is what used to drift.
      appearances: Draft.appearances(item.draft),
      destination: Inbox.destination_preflight(item),
      # Matching retries with a backoff measured in minutes, so an item can be
      # legitimately mid-work while the form looks like nothing was found.
      job: job,
      # a job is going to change this draft, so the form is not editable yet
      busy: Inbox.busy?(job),
      # Roots are configuration and can change between seeding a draft and
      # approving it, so they're read now rather than frozen into the draft.
      roots: Ambry.Library.list_roots()
    )
    |> schedule_tick()
  end

  defp atom("work"), do: :work
  defp atom("recording"), do: :recording
  defp atom("title"), do: :title
  defp atom("published"), do: :published
  defp atom("publisher"), do: :publisher
  defp atom("description"), do: :description
  defp atom("cover"), do: :cover

  defp group_options(%Draft{work: %Work{mode: :link, book_id: book_id}}) when not is_nil(book_id),
    do: Media.recording_groups_for_select(book_id)

  defp group_options(_draft), do: []

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

  ## rendering helpers

  @doc """
  What a background job is doing to this item, if anything.

  The form is where somebody looks when a match seems wrong, and "still
  working" is a completely different answer from "nothing was found" —
  especially now that a rate-limited provider means minutes of backoff rather
  than an immediate give-up.
  """
  def job_label(:working), do: {"Still matching…", :blue}
  def job_label(:retrying), do: {"A provider couldn't be reached — waiting to try again", :yellow}
  def job_label(:queued), do: {"Queued for matching", :blue}
  def job_label(:failed), do: {"Matching gave up — try Start over", :red}
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
  How many chapters the files carry, and where the markers came from.

  Markers are file-derived by principle — provider chapter times describe
  their own retail edition, and applying them to somebody's rip drifts by
  minutes across a book. Provider data is a *title* source only, poured onto
  these markers afterwards in the chapter editor (roadmap 1h).
  """
  def chapter_summary(%InboxItem{probe: %{"chapters" => count} = probe}) when count > 0,
    do: "#{count} chapters, #{marker_source_phrase(probe["chapter_marker_source"])}."

  def chapter_summary(%InboxItem{probe: probe}) when is_map(probe),
    do: "No chapters in the files. The recording will have none until they're added."

  def chapter_summary(_item), do: "Not read yet."

  defp marker_source_phrase("file_boundaries"), do: "one per file, from where each file starts"
  defp marker_source_phrase(_embedded_or_unknown), do: "read from the files"

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
      "No provider had a recording matching this. That is common and not a problem — " <>
        "a delisted edition vanishes from Audible's search and from ASIN lookup alike. " <>
        "The fields below come from the file's own tags."

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

  # Shaped like a stored local record, so the row component can't tell a
  # searched-for book from a matched one — they are the same answer.
  defp local_book(book) do
    %{
      "id" => book.id,
      "title" => book.title,
      "authors" => Enum.map(book.authors || [], & &1.name),
      "published" => book.published && Date.to_iso8601(book.published)
    }
  end

  @doc "How a provider record is referred to."
  defdelegate record_ref(record), to: Inbox

  @doc "The provider records found for a level."
  defdelegate records(item, level), to: Seed

  @doc "Existing Books this release might be another edition of."
  defdelegate local_records(item, level), to: Seed
end
