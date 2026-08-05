defmodule AmbryWeb.Admin.InboxLive.Form do
  @moduledoc """
  The staged import form: everything this release will become, before any of
  it is real.

  Built on one invariant — **an import is a tree of decisions, and import is
  possible iff every decision is resolved**. The button at the bottom reads
  `Draft.unresolved/1` and nothing else, which is what guarantees the form
  never offers an action that fails: everything that could go wrong at
  approval was a visible decision before the button was pressed.

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
     |> assign(people: People.people_for_select())
     |> assign(expanded: MapSet.new())
     |> assign(researching: nil, retrying: nil, enriching: nil, picker: nil)
     |> load(item)}
  end

  @doc """
  Whether a credit's person layer should be showing.

  Folded away for the ordinary case — one new person of the same name — and
  unfolded whenever the credit is anything else, so a pen name can never be
  hiding behind a collapsed control.
  """
  def expanded?(expanded, section, index, credit) do
    MapSet.member?(expanded, {section, index}) or not Credit.simple?(credit)
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

    {:noreply,
     edit(socket, fn draft ->
       if id do
         Draft.Edit.link_credit(draft, section, index, id)
       else
         draft
         |> Draft.Edit.create_credit(section, index)
         |> Draft.Edit.rename_credit(section, index, params["name"] || "")
       end
     end)}
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

  def handle_event("find-person-images", params, socket) do
    %{"section" => section, "index" => index, "person" => person} = params
    credit = credit_at(socket.assigns.item.draft, atom(section), to_int(index))
    person_ref = Enum.at(credit.people, to_int(person))

    {:noreply,
     assign(socket,
       picker: %{
         section: section,
         index: to_int(index),
         person: to_int(person),
         query: person_ref.name || credit.name
       }
     )}
  end

  def handle_event("close-picker", _params, socket), do: {:noreply, assign(socket, picker: nil)}

  def handle_event("add-person", %{"section" => section, "index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.add_person(&1, atom(section), to_int(i)))}
  end

  def handle_event("remove-person", %{"section" => s, "index" => i, "person" => p}, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_person(&1, atom(s), to_int(i), to_int(p)))}
  end

  def handle_event(
        "person-change",
        %{"section" => s, "index" => i, "person" => p} = params,
        socket
      ) do
    # An existing person is chosen by id; anything else is a name to create.
    attrs =
      case to_int(params["person_id"]) do
        nil -> %{name: params["name"] || "", person_id: nil}
        id -> %{person_id: id, name: nil}
      end

    {:noreply, edit(socket, &Draft.Edit.set_person(&1, atom(s), to_int(i), to_int(p), attrs))}
  end

  def handle_event("approve-credit", %{"section" => s, "index" => i} = params, socket) do
    {:noreply,
     edit(
       socket,
       &Draft.Edit.approve_credit(&1, atom(s), to_int(i), params["approved"] == "true")
     )}
  end

  def handle_event("remove-credit", %{"section" => s, "index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_credit(&1, atom(s), to_int(i)))}
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

  def handle_event("approve-work", params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_work(&1, params["approved"] == "true"))}
  end

  def handle_event("choose-root", %{"root_id" => root_id}, socket) do
    id = to_int(root_id)

    {:noreply,
     edit(socket, fn draft ->
       update_in(draft.destination, &%{&1 | root_id: id, approved: not is_nil(id)})
     end)}
  end

  def handle_event("approve-all", _params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_all/1)}
  end

  def handle_event("rebuild", _params, socket) do
    {:ok, item} = Inbox.rebuild_draft(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Started over from what the files and providers say.")
     |> load(item)}
  end

  def handle_event("import", _params, socket) do
    case Inbox.approve_item(socket.assigns.item) do
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

  def handle_event("dismiss", _params, socket) do
    {:ok, _item} = Inbox.dismiss_item(socket.assigns.item)

    {:noreply,
     socket
     |> put_flash(:info, "Dismissed. Files untouched.")
     |> push_navigate(to: ~p"/admin/inbox")}
  end

  @impl Phoenix.LiveView
  def handle_info({:person_image_picked, context, url, source}, socket) do
    {:noreply,
     socket
     |> assign(picker: nil)
     |> edit(
       &Draft.Edit.set_person_image(
         &1,
         atom(context.section),
         context.index,
         context.person,
         url,
         source
       )
     )}
  end

  def handle_info({:person_bio_picked, context, description, source}, socket) do
    {:noreply,
     socket
     |> assign(picker: nil)
     |> edit(
       &Draft.Edit.set_person_bio(
         &1,
         atom(context.section),
         context.index,
         context.person,
         description,
         source
       )
     )}
  end

  @impl Phoenix.LiveView
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
    assign(socket,
      item: item,
      form: to_form(Inbox.change_draft(item)),
      unresolved: Draft.unresolved(item.draft),
      progress: Draft.progress(item.draft),
      destination: Inbox.destination_preflight(item),
      # Matching retries with a backoff measured in minutes, so an item can be
      # legitimately mid-work while the form looks like nothing was found.
      job: Inbox.job_status(item),
      # Roots are configuration and can change between seeding a draft and
      # approving it, so they're read now rather than frozen into the draft.
      roots: Ambry.Library.library_roots()
    )
  end

  defp atom("work"), do: :work
  defp atom("recording"), do: :recording
  defp atom("title"), do: :title
  defp atom("published"), do: :published
  defp atom("published_format"), do: :published_format
  defp atom("publisher"), do: :publisher
  defp atom("description"), do: :description
  defp atom("cover"), do: :cover

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
      probe["codec"],
      probe["chapters"] && probe["chapters"] > 0 && "#{probe["chapters"]} chapters",
      probe["seek_accuracy"] == "approximate" && "inexact seeking"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  def evidence(_item), do: "not read yet"

  @doc """
  How many chapters the file carries, and where they came from.

  Markers are file-derived by principle — provider chapter times describe
  their own retail edition, and applying them to somebody's rip drifts by
  minutes across a book. Provider data is a *title* source only, which is 1h's
  work and not part of this form yet.
  """
  def chapter_summary(%InboxItem{probe: %{"chapters" => count}}) when count > 0,
    do: "#{count} chapters, read from the file."

  def chapter_summary(%InboxItem{probe: probe}) when is_map(probe),
    do: "No chapters in the file. The recording will have none until they're added."

  def chapter_summary(_item), do: "Not read yet."

  @doc """
  What this import says the release is, in one line.

  The form asks two questions — which book, which recording — but they are two
  halves of one fact: a file is a recording of exactly one work. Stating the
  answer as a sentence is how the operator checks it at a glance instead of
  reassembling it from six fields.
  """
  def identity_summary(%Draft{} = draft) do
    title = Field.value(draft.work.title) || "an unidentified book"
    authors = names_of(draft.work.authors)
    narrators = names_of(draft.recording.narrators)

    [
      title,
      authors != "" && "by #{authors}",
      narrators != "" && "read by #{narrators}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  def identity_summary(_draft), do: nil

  defp names_of(credits), do: Enum.map_join(credits, ", ", & &1.name)

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

  defp credit_at(draft, :work, index), do: Enum.at(draft.work.authors, index)
  defp credit_at(draft, :recording, index), do: Enum.at(draft.recording.narrators, index)

  @doc "How a provider record is referred to."
  defdelegate record_ref(record), to: Inbox

  @doc "The provider records found for a level."
  defdelegate records(item, level), to: Seed

  @doc "Existing Books this release might be another edition of."
  defdelegate local_records(item, level), to: Seed

  @doc """
  How many decisions the bulk button would settle, so its label can say.

  A button that might do fourteen things or nothing should not look the same
  in both cases.
  """
  def settleable(unresolved) do
    Enum.count(unresolved, &(&1.state != :missing))
  end

  def confidence_label(nil), do: {"no match", :gray}
  def confidence_label(confidence) when confidence >= 0.85, do: {"near-certain", :brand}
  def confidence_label(confidence) when confidence >= 0.6, do: {"likely", :blue}
  def confidence_label(confidence) when confidence > 0.0, do: {"unsure", :yellow}
  def confidence_label(_confidence), do: {"no match", :gray}
end
