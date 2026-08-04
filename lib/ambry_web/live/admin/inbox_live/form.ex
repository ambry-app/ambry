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

  Credits read "Credited as" / "Written by" (or "Performed by"), which is what
  makes the two-level identity model legible without explaining it: the
  identity is what the book credits, the people are the humans behind it, and
  two or more of them is a shared pen name. That is the entire composite-author
  case — a longer list, not a different mode.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.Decisions
  import AmbryWeb.TimeUtils

  alias Ambry.Books
  alias Ambry.Inbox
  alias Ambry.Inbox.Draft
  alias Ambry.Inbox.Draft.Work
  alias Ambry.Inbox.InboxItem
  alias Ambry.People

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
     |> load(item)}
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
     edit(socket, &Draft.Edit.choose_field(&1, atom(section), atom(field), params["source"]))}
  end

  def handle_event("waive-field", %{"section" => section, "field" => field}, socket) do
    {:noreply, edit(socket, &Draft.Edit.waive_field(&1, atom(section), atom(field)))}
  end

  def handle_event("choose-work", %{"source" => source} = params, socket) do
    {:noreply, edit(socket, &Draft.Edit.choose_work(&1, source, to_int(params["id"])))}
  end

  def handle_event("link-credit", %{"section" => section, "index" => i} = params, socket) do
    id = to_int(params["identity_id"])

    {:noreply,
     edit(socket, fn draft ->
       if id,
         do: Draft.Edit.link_credit(draft, atom(section), to_int(i), id),
         else: Draft.Edit.create_credit(draft, atom(section), to_int(i))
     end)}
  end

  def handle_event("add-person", %{"section" => section, "index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.add_person(&1, atom(section), to_int(i)))}
  end

  def handle_event("remove-person", %{"section" => s, "index" => i, "person" => p}, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_person(&1, atom(s), to_int(i), to_int(p)))}
  end

  def handle_event("set-person", %{"section" => s, "index" => i, "person" => p} = params, socket) do
    # An existing person is chosen by id; anything else is a name to create.
    attrs =
      case to_int(params["person_id"]) do
        nil -> %{name: params["name"], person_id: nil}
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
    id = to_int(params["series_id"])

    {:noreply,
     edit(socket, fn draft ->
       if id,
         do: Draft.Edit.link_series(draft, to_int(i), id),
         else: Draft.Edit.create_series(draft, to_int(i))
     end)}
  end

  def handle_event("remove-series", %{"index" => i}, socket) do
    {:noreply, edit(socket, &Draft.Edit.remove_series(&1, to_int(i)))}
  end

  def handle_event("approve-work", params, socket) do
    {:noreply, edit(socket, &Draft.Edit.approve_work(&1, params["approved"] == "true"))}
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
      destination: Inbox.destination_preflight(item)
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
  Whether this candidate is the one the work decision currently points at.
  """
  def chosen_work?(%Work{mode: :link, book_id: id}, %{"source" => "local", "id" => id}), do: true
  def chosen_work?(%Work{mode: :link}, _candidate), do: false
  def chosen_work?(%Work{mode: :create}, %{"source" => "local"}), do: false

  # Any non-local candidate means "create a new book"; which provider it came
  # from is recorded per-field as provenance, not as one winning row.
  def chosen_work?(%Work{mode: :create, approved: approved?}, _candidate), do: approved?

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

  def outcome_label(%{"status" => "failed"} = outcome),
    do: {"#{outcome["name"]} couldn't be reached", :red}

  def outcome_label(%{"count" => 0} = outcome), do: {"#{outcome["name"]}: nothing", :gray}

  def outcome_label(outcome), do: {"#{outcome["name"]}: #{outcome["count"]}", :gray}

  @doc "A work candidate as one readable line."
  def candidate_line(candidate) do
    [candidate["title"], candidate["authors"] && Enum.join(candidate["authors"], ", ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" — ")
  end

  def candidate_origin(%{"source" => "local"}), do: "already in the library"
  def candidate_origin(%{"provider_name" => name}) when is_binary(name), do: name
  def candidate_origin(%{"source" => "provider:" <> id}), do: id
  def candidate_origin(_candidate), do: nil

  def confidence_label(nil), do: {"no match", :gray}
  def confidence_label(confidence) when confidence >= 0.85, do: {"near-certain", :brand}
  def confidence_label(confidence) when confidence >= 0.6, do: {"likely", :blue}
  def confidence_label(confidence) when confidence > 0.0, do: {"unsure", :yellow}
  def confidence_label(_confidence), do: {"no match", :gray}
end
